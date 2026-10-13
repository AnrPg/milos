defmodule MilosTraining.Finance.Domain.PackageContract do
  @moduledoc """
  Pure normaliser for package writes (ADR-096).

  It merges submitted fields onto the type preset (or the existing contract
  when the type is unchanged), validates every value against the catalog,
  pins type-enforced values, keeps unimplemented fields at their preset value
  and applies the type's cross-field rules. The result is a complete field map
  that is stored as `params.fields` with `entitlement_version: 2`.
  """

  alias MilosTraining.Finance.Domain.{
    EntitlementPlan,
    PackageCatalog,
    PackagePresets,
    PackageType
  }

  @version 2

  def version, do: @version

  @doc """
  Normalizes `%{"package_type" => ..., "billing_period" => ..., "fields" => ...}`.

  Options:
    * `:existing` - the stored `%{package_type:, billing_period:, fields:}` when updating.
  """
  def normalize(input, opts \\ []) when is_map(input) do
    existing = Keyword.get(opts, :existing)
    type_key = get(input, "package_type") || (existing && existing.package_type)

    with {:ok, type} <- PackageType.fetch(type_key),
         :ok <- ensure_type_available(type),
         {:ok, billing_period} <- billing_period(type, input, existing),
         {:ok, preset} <- PackagePresets.preset(type_key, billing_period),
         {:ok, submitted} <- cast_fields(get(input, "fields") || %{}),
         {:ok, merged} <- merge(base_fields(type_key, preset, existing), submitted),
         {:ok, fields} <- pin_unavailable(merged, submitted, preset),
         {:ok, fields} <- pin_locks(fields, submitted, type_key),
         :ok <- validate_rules(type_key, fields) do
      {:ok, %{package_type: type_key, billing_period: billing_period, fields: fields}}
    end
  end

  @doc "Params document stored on the package and snapshotted on subscriptions."
  def to_params(%{package_type: type, fields: fields}) do
    %{"entitlement_version" => @version, "package_type" => type, "fields" => fields}
  end

  @doc """
  Field map for any stored params document. Legacy v1 plans are presented as
  an equivalent membership contract so the editor can migrate them on save.
  """
  def fields_from_params(params) when is_map(params) do
    case get(params, "entitlement_version") do
      @version ->
        {:ok, preset} = PackagePresets.preset(get(params, "package_type") || "membership")
        Map.merge(preset, get(params, "fields") || %{})

      1 ->
        case EntitlementPlan.parse(params) do
          {:ok, plan} -> from_v1(plan)
          _ -> membership_preset()
        end

      _ ->
        membership_preset()
    end
  end

  def fields_from_params(_), do: membership_preset()

  @doc "Package type recorded in a params document, defaulting legacy plans to membership."
  def type_from_params(params) when is_map(params) do
    case get(params, "entitlement_version") do
      @version -> get(params, "package_type") || "membership"
      _ -> "membership"
    end
  end

  def type_from_params(_), do: "membership"

  @doc "Field keys whose value differs from the type preset (for 'changed' markers)."
  def changed_fields(type_key, billing_period, fields) do
    case PackagePresets.preset(type_key, billing_period) do
      {:ok, preset} ->
        fields
        |> Enum.filter(fn {key, value} -> Map.get(preset, key) != value end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp from_v1(plan) do
    preset = membership_preset()
    classes? = MapSet.member?(plan.channels, :in_person)
    programming? = MapSet.member?(plan.channels, :personal_programming)
    messaging? = MapSet.member?(plan.channels, :coach_messaging)

    preset
    |> Map.put("group_classes.included", classes?)
    |> maybe_put_quota("group_classes.visits", Map.get(plan.allowances, :class_visits))
    |> Map.put("online_coaching.included", programming? or messaging?)
    |> Map.put("online_coaching.assigned_programming", programming? or not messaging?)
    |> Map.put("online_coaching.messaging", messaging?)
    |> maybe_put_quota(
      "online_coaching.touchpoints",
      Map.get(plan.allowances, :coaching_touchpoints)
    )
  end

  defp maybe_put_quota(fields, _key, nil), do: fields

  defp maybe_put_quota(fields, key, %{limit: limit, period: period}) do
    Map.put(fields, key, %{
      "limit" => if(limit == :unlimited, do: "unlimited", else: limit),
      "period" => Atom.to_string(period)
    })
  end

  defp membership_preset do
    {:ok, preset} = PackagePresets.preset("membership")
    preset
  end

  defp ensure_type_available(type) do
    if PackageType.available?(type), do: :ok, else: {:error, :package_type_not_available}
  end

  defp billing_period(type, input, existing) do
    requested =
      get(input, "billing_period") ||
        (existing && existing.package_type == type.key && existing.billing_period) ||
        PackageType.default_billing_period(type)

    if requested in PackageType.billing_periods(type),
      do: {:ok, requested},
      else: {:error, {:package_type_invariant_violated, "billing_period"}}
  end

  defp base_fields(type_key, preset, %{package_type: type_key, fields: fields})
       when is_map(fields),
       do: Map.merge(preset, Map.take(fields, PackageCatalog.keys()))

  defp base_fields(_type_key, preset, _existing), do: preset

  defp cast_fields(fields) when is_map(fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      with {:ok, spec} <- PackageCatalog.fetch(key),
           {:ok, cast} <- cast_field(spec, value) do
        {:cont, {:ok, Map.put(acc, key, cast)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp cast_fields(_), do: {:error, :invalid_package_fields}

  defp cast_field(spec, value) do
    case PackageCatalog.cast(spec, value) do
      {:ok, cast} -> {:ok, cast}
      {:error, reason} -> {:error, {:invalid_package_field, spec.key, reason}}
    end
  end

  defp merge(base, submitted), do: {:ok, Map.merge(base, submitted)}

  defp pin_unavailable(fields, submitted, preset) do
    Enum.reduce_while(PackageCatalog.fields(), {:ok, fields}, fn spec, {:ok, acc} ->
      cond do
        PackageCatalog.available?(spec) ->
          {:cont, {:ok, acc}}

        Map.has_key?(submitted, spec.key) and submitted[spec.key] != preset[spec.key] ->
          {:halt, {:error, {:entitlement_not_available, spec.key}}}

        true ->
          {:cont, {:ok, Map.put(acc, spec.key, preset[spec.key])}}
      end
    end)
  end

  defp pin_locks(fields, submitted, type_key) do
    type_key
    |> PackagePresets.locks()
    |> Enum.reduce_while({:ok, fields}, fn {path, locked, _reason}, {:ok, acc} ->
      field = PackagePresets.lock_field(path)

      if Map.has_key?(submitted, field) and
           PackagePresets.locked_value(submitted[field], path) != locked do
        {:halt, {:error, {:package_type_invariant_violated, path}}}
      else
        {:cont, {:ok, Map.put(acc, field, put_locked(acc[field], path, locked))}}
      end
    end)
  end

  defp put_locked(value, path, locked) do
    case String.split(path, ".") do
      [_, _] -> locked
      [_, _, sub_key] -> Map.put(value || %{}, sub_key, locked)
    end
  end

  defp validate_rules(type_key, fields) do
    {:ok, type} = PackageType.fetch(type_key)

    [
      {PackageType.one_off?(type) and is_nil(fields["terms.validity"]), :validity_required,
       "terms.validity"},
      {type_key == "class_pack" and not limited?(fields["group_classes.visits"]),
       :limited_quota_required, "group_classes.visits"},
      {type_key == "pt_pack" and not limited?(fields["personal_training.sessions"]),
       :limited_quota_required, "personal_training.sessions"},
      {limited?(fields["group_classes.visits"]) and fields["group_classes.visits"]["limit"] < 1 and
         fields["group_classes.included"], :positive_quota_required, "group_classes.visits"},
      {not any_service?(fields), :at_least_one_service, "group_classes.included"},
      {fields["online_coaching.included"] and not fields["online_coaching.assigned_programming"] and
         not fields["online_coaching.messaging"], :coaching_channel_required,
       "online_coaching.included"},
      {type_key == "shared" and fields["terms.beneficiaries"] < 2, :beneficiaries_min_two,
       "terms.beneficiaries"},
      {invalid_group_size?(fields), :group_size_matches_format, "personal_training.group_size"},
      {limits_outside_scope?(fields), :class_type_limit_outside_scope,
       "group_classes.class_type_limits"},
      {fields["perks.member_discount_percent"] > 0 and
         fields["perks.member_discount_scope"] == [], :discount_scope_required,
       "perks.member_discount_scope"},
      {is_binary(fields["terms.conversion_package_id"]) and type_key != "trial",
       :conversion_only_for_trials, "terms.conversion_package_id"}
    ]
    |> Enum.find(fn {violated?, _rule, _field} -> violated? end)
    |> case do
      nil -> :ok
      {true, rule, field} -> {:error, {:package_rule_violated, rule, field}}
    end
  end

  defp limited?(%{"limit" => limit}) when is_integer(limit), do: true
  defp limited?(_), do: false

  defp any_service?(fields) do
    Enum.any?(
      [
        "group_classes.included",
        "online_coaching.included",
        "personal_training.included",
        "facility.open_gym",
        "content.on_demand_video",
        "content.advanced_analytics",
        "online_coaching.nutrition_plan",
        "perks.events"
      ],
      &(fields[&1] == true)
    )
  end

  defp invalid_group_size?(fields) do
    case {fields["personal_training.format"], fields["personal_training.group_size"]} do
      {"one_to_one", size} -> size != 1
      {"semi_private", size} -> size < 2 or size > 4
      _ -> false
    end
  end

  defp limits_outside_scope?(fields) do
    case fields["group_classes.class_types"] do
      "all" ->
        false

      ids when is_list(ids) ->
        Enum.any?(fields["group_classes.class_type_limits"] || [], &(&1["id"] not in ids))
    end
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))
end
