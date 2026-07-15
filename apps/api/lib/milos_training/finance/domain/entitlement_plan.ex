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

  defstruct version: 1,
            channels: MapSet.new(),
            capabilities: MapSet.new(),
            allowances: %{}

  def parse(%__MODULE__{} = plan), do: {:ok, plan}

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
