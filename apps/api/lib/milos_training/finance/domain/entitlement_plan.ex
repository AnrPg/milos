defmodule MilosTraining.Finance.Domain.EntitlementPlan do
  @moduledoc """
  Pure parser for the versioned product contract stored in package params.

  The parser uses closed vocabularies and never creates atoms from customer
  input. Package family and tags deliberately have no authorization meaning.
  """

  @channels ~w[in_person workout_library personal_programming coach_messaging]a
  @capabilities ~w[
    book_classes execute_class_workouts execute_library_workouts
    execute_assigned_workouts receive_coaching_touchpoints
  ]a
  @allowances ~w[class_visits coaching_touchpoints]a
  @periods ~w[calendar_week calendar_month subscription_period]a

  @class_type_allowance_prefix "class_visits:"

  defstruct version: 1,
            package_type: nil,
            channels: MapSet.new(),
            capabilities: MapSet.new(),
            allowances: %{},
            class_type_scope: :all

  def parse(%__MODULE__{} = plan), do: {:ok, plan}

  def parse(%{"entitlement_version" => 2} = params), do: compile_v2(params)
  def parse(%{entitlement_version: 2} = params), do: compile_v2(stringify(params))

  def parse(params) when is_map(params) do
    with {:ok, version} <- parse_version(value(params, "entitlement_version")),
         {:ok, channels} <- parse_enum_set(value(params, "channels", []), @channels, :channel),
         {:ok, capabilities} <-
           parse_enum_set(value(params, "capabilities", []), @capabilities, :capability),
         {:ok, allowances} <- parse_allowances(value(params, "allowances", %{})) do
      {:ok,
       %__MODULE__{
         version: version,
         channels: channels,
         capabilities: capabilities,
         allowances: allowances
       }}
    end
  end

  def parse(_), do: {:error, :invalid_entitlement_plan}

  def valid_channels, do: @channels
  def valid_capabilities, do: @capabilities
  def valid_allowances, do: @allowances
  def valid_periods, do: @periods

  @doc """
  Ledger allowance key for a request. A class type with its own limit consumes
  that limit instead of the general class-visit allowance (ADR-096).
  """
  def resolve_allowance(%__MODULE__{} = plan, :class_visits, class_type_id)
      when is_binary(class_type_id) do
    key = class_type_allowance_key(class_type_id)
    if Map.has_key?(plan.allowances, key), do: key, else: :class_visits
  end

  def resolve_allowance(_plan, allowance, _class_type_id), do: allowance

  def class_type_allowance_key(class_type_id),
    do: @class_type_allowance_prefix <> class_type_id

  def class_type_allowance_key?(key) when is_binary(key),
    do: String.starts_with?(key, @class_type_allowance_prefix)

  def class_type_allowance_key?(_), do: false

  def class_type_included?(%__MODULE__{class_type_scope: :all}, _class_type_id), do: true
  def class_type_included?(_plan, nil), do: true

  def class_type_included?(%__MODULE__{class_type_scope: scope}, class_type_id),
    do: MapSet.member?(scope, class_type_id)

  defp compile_v2(params) do
    fields = MilosTraining.Finance.Domain.PackageContract.fields_from_params(params)

    with {:ok, fields} <- validate_v2_fields(fields) do
      classes? = fields["group_classes.included"] == true
      coaching? = fields["online_coaching.included"] == true
      programming? = coaching? and fields["online_coaching.assigned_programming"] == true
      messaging? = coaching? and fields["online_coaching.messaging"] == true

      channels =
        []
        |> add_if(classes?, :in_person)
        |> add_if(programming?, :personal_programming)
        |> add_if(messaging?, :coach_messaging)

      capabilities =
        []
        |> add_if(classes?, [:book_classes, :execute_class_workouts])
        |> add_if(programming?, :execute_assigned_workouts)
        |> add_if(coaching?, :receive_coaching_touchpoints)

      allowances =
        %{}
        |> put_quota_if(classes?, :class_visits, fields["group_classes.visits"])
        |> put_quota_if(coaching?, :coaching_touchpoints, fields["online_coaching.touchpoints"])
        |> put_class_type_quotas(classes?, fields["group_classes.class_type_limits"])

      {:ok,
       %__MODULE__{
         version: 2,
         package_type: params["package_type"] || "membership",
         channels: MapSet.new(channels),
         capabilities: MapSet.new(capabilities),
         allowances: allowances,
         class_type_scope: class_type_scope(fields["group_classes.class_types"])
       }}
    end
  end

  defp validate_v2_fields(fields) do
    alias MilosTraining.Finance.Domain.PackageCatalog

    Enum.reduce_while(fields, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, spec} <- PackageCatalog.fetch(key),
           {:ok, cast} <- PackageCatalog.cast(spec, value) do
        {:cont, {:ok, Map.put(acc, key, cast)}}
      else
        {:error, {:unknown_package_field, _} = reason} -> {:halt, {:error, reason}}
        {:error, reason} -> {:halt, {:error, {:invalid_package_field, key, reason}}}
      end
    end)
  end

  defp add_if(list, false, _value), do: list
  defp add_if(list, true, values) when is_list(values), do: list ++ values
  defp add_if(list, true, value), do: list ++ [value]

  defp put_quota_if(allowances, false, _key, _quota), do: allowances

  defp put_quota_if(allowances, true, key, %{"limit" => limit, "period" => period}),
    do: Map.put(allowances, key, quota(limit, period))

  defp put_class_type_quotas(allowances, false, _limits), do: allowances

  defp put_class_type_quotas(allowances, true, limits) do
    Enum.reduce(limits || [], allowances, fn %{"id" => id} = limit, acc ->
      Map.put(acc, class_type_allowance_key(id), quota(limit["limit"], limit["period"]))
    end)
  end

  defp quota(limit, period) do
    %{
      limit: if(limit == "unlimited", do: :unlimited, else: limit),
      period: known_atom(period, @periods),
      counted_kinds: []
    }
  end

  defp class_type_scope("all"), do: :all
  defp class_type_scope(ids) when is_list(ids), do: MapSet.new(ids)

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp parse_version(1), do: {:ok, 1}
  defp parse_version(_), do: {:error, :unsupported_entitlement_version}

  defp parse_enum_set(values, allowed, kind) when is_list(values) do
    Enum.reduce_while(values, {:ok, MapSet.new()}, fn value, {:ok, acc} ->
      case known_atom(value, allowed) do
        nil -> {:halt, {:error, {unknown_error(kind), to_string(value)}}}
        atom -> {:cont, {:ok, MapSet.put(acc, atom)}}
      end
    end)
  end

  defp parse_enum_set(_, _, _), do: {:error, :invalid_entitlement_plan}

  defp parse_allowances(allowances) when is_map(allowances) do
    Enum.reduce_while(allowances, {:ok, %{}}, fn {key, config}, {:ok, acc} ->
      case known_atom(key, @allowances) do
        nil ->
          {:halt, {:error, {:unknown_allowance, to_string(key)}}}

        allowance ->
          case parse_allowance(to_string(key), config) do
            {:ok, normalized} -> {:cont, {:ok, Map.put(acc, allowance, normalized)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp parse_allowances(_), do: {:error, :invalid_entitlement_plan}

  defp parse_allowance(key, config) when is_map(config) do
    limit = value(config, "limit")
    period = known_atom(value(config, "period"), @periods)

    cond do
      limit != "unlimited" and limit != :unlimited and
          not (is_integer(limit) and limit >= 0) ->
        {:error, {:invalid_allowance_limit, key}}

      is_nil(period) ->
        {:error, {:invalid_allowance_period, key}}

      true ->
        {:ok,
         %{
           limit: if(limit in ["unlimited", :unlimited], do: :unlimited, else: limit),
           period: period,
           counted_kinds: List.wrap(value(config, "counted_kinds", []))
         }}
    end
  end

  defp parse_allowance(key, _), do: {:error, {:invalid_allowance, key}}

  defp known_atom(value, allowed) when is_atom(value), do: if(value in allowed, do: value)

  defp known_atom(value, allowed) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value))
  end

  defp known_atom(_, _), do: nil

  defp unknown_error(:channel), do: :unknown_channel
  defp unknown_error(:capability), do: :unknown_capability

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, String.to_existing_atom(key), default))
  rescue
    ArgumentError -> Map.get(map, key, default)
  end
end
