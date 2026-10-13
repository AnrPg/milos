defmodule MilosTraining.Finance.Domain.EntitlementPlan do
  @moduledoc """
  Pure parser for the versioned product contract stored in package params.

  The parser uses closed vocabularies and never creates atoms from customer
  input. Package family and tags deliberately have no authorization meaning.
  """

  @channels ~w[
    in_person workout_library personal_programming coach_messaging events facility
    personal_training digital_content nutrition
  ]a
  @capabilities ~w[
    book_classes execute_class_workouts execute_library_workouts
    execute_assigned_workouts receive_coaching_touchpoints
    book_events bring_guests open_gym
    book_pt_sessions book_assessments request_form_reviews receive_nutrition_plan
    watch_on_demand view_advanced_analytics
  ]a
  @allowances ~w[
    class_visits coaching_touchpoints event_visits guest_passes open_gym_visits
    pt_sessions assessments form_reviews
  ]a
  @periods ~w[calendar_week calendar_month subscription_period]a

  @class_type_allowance_prefix "class_visits:"

  defstruct version: 1,
            package_type: nil,
            channels: MapSet.new(),
            capabilities: MapSet.new(),
            allowances: %{},
            class_type_scope: :all,
            location_scope: :all,
            time_windows: [],
            terms: %{}

  def parse(%__MODULE__{} = plan), do: {:ok, plan}

  def parse(%{"compiled" => true} = params), do: parse_compiled(params)
  def parse(%{compiled: true} = params), do: parse_compiled(stringify(params))
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
      events? = fields["perks.events"] == true
      open_gym? = fields["facility.open_gym"] == true
      guests? = classes? and quota_granted?(fields["perks.guest_passes"])
      # Phase C services (ADR-098).
      pt? = fields["personal_training.included"] == true
      assessments? = positive?(fields["personal_training.assessments"])
      form_reviews? = coaching? and quota_granted?(fields["online_coaching.form_reviews"])
      nutrition? = fields["online_coaching.nutrition_plan"] == true
      video? = fields["content.on_demand_video"] == true
      analytics? = fields["content.advanced_analytics"] == true

      channels =
        []
        |> add_if(classes?, :in_person)
        |> add_if(programming?, :personal_programming)
        |> add_if(messaging?, :coach_messaging)
        |> add_if(events?, :events)
        |> add_if(open_gym?, :facility)
        |> add_if(pt? or assessments?, :personal_training)
        |> add_if(video? or analytics?, :digital_content)
        |> add_if(nutrition?, :nutrition)

      capabilities =
        []
        |> add_if(classes?, [:book_classes, :execute_class_workouts])
        |> add_if(programming?, :execute_assigned_workouts)
        |> add_if(coaching?, :receive_coaching_touchpoints)
        |> add_if(events?, [:book_events, :execute_class_workouts])
        |> add_if(guests?, :bring_guests)
        |> add_if(open_gym?, :open_gym)
        |> add_if(pt?, :book_pt_sessions)
        |> add_if(assessments?, :book_assessments)
        |> add_if(form_reviews?, :request_form_reviews)
        |> add_if(nutrition?, :receive_nutrition_plan)
        |> add_if(video?, :watch_on_demand)
        |> add_if(analytics?, :view_advanced_analytics)

      allowances =
        %{}
        |> put_quota_if(classes?, :class_visits, fields["group_classes.visits"])
        |> put_quota_if(coaching?, :coaching_touchpoints, fields["online_coaching.touchpoints"])
        |> put_class_type_quotas(classes?, fields["group_classes.class_type_limits"])
        |> put_quota_if(events?, :event_visits, fields["perks.event_visits"])
        |> put_quota_if(guests?, :guest_passes, fields["perks.guest_passes"])
        |> put_quota_if(open_gym?, :open_gym_visits, fields["facility.open_gym_visits"])
        |> put_quota_if(pt?, :pt_sessions, fields["personal_training.sessions"])
        |> put_quota_if(assessments?, :assessments, %{
          "limit" => fields["personal_training.assessments"],
          "period" => "subscription_period"
        })
        |> put_quota_if(form_reviews?, :form_reviews, fields["online_coaching.form_reviews"])

      {:ok,
       %__MODULE__{
         version: 2,
         package_type: params["package_type"] || "membership",
         channels: MapSet.new(channels),
         capabilities: MapSet.new(capabilities),
         allowances: allowances,
         class_type_scope: class_type_scope(fields["group_classes.class_types"]),
         location_scope: class_type_scope(fields["facility.location_ids"]),
         time_windows: fields["group_classes.time_windows"] || [],
         terms: terms(fields)
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

  defp positive?(value), do: is_integer(value) and value > 0

  defp quota_granted?(%{"limit" => 0}), do: false
  defp quota_granted?(%{"limit" => _}), do: true
  defp quota_granted?(_), do: false

  # Contract terms read by enforcement outside the allowance ledger (ADR-097).
  defp terms(fields) do
    %{
      booking_window_days: fields["booking.window_days"],
      cancellation_cutoff_hours: fields["booking.cancellation_cutoff_hours"],
      waitlist_priority: fields["booking.waitlist_priority"] || "normal",
      no_show_penalty_waived: fields["booking.no_show_penalty_waived"] == true,
      rollover_max: fields["group_classes.rollover_max"] || 0,
      freeze_days_per_year: fields["perks.freeze_days_per_year"] || 0,
      member_discount_percent: fields["perks.member_discount_percent"] || 0,
      member_discount_scope: fields["perks.member_discount_scope"] || [],
      minimum_commitment_months: fields["terms.minimum_commitment_months"] || 0,
      joining_fee_cents: fields["terms.joining_fee_cents"] || 0,
      validity_starts: fields["terms.validity_starts"] || "purchase",
      expiry_reminder_days: fields["terms.expiry_reminder_days"] || 0,
      validity: fields["terms.validity"],
      auto_renew: fields["terms.auto_renew"],
      # Phase C (ADR-098)
      response_sla_hours: fields["online_coaching.response_sla_hours"],
      pt_format: fields["personal_training.format"],
      pt_group_size: fields["personal_training.group_size"],
      pt_session_minutes: fields["personal_training.session_minutes"],
      pt_coach_id: fields["personal_training.coach_id"],
      compatible_package_ids: fields["terms.compatible_package_ids"] || "all",
      beneficiaries: fields["terms.beneficiaries"] || 1,
      quota_sharing: fields["terms.quota_sharing"] || "per_person",
      allow_minor_beneficiaries: fields["terms.allow_minor_beneficiaries"] == true,
      seats: fields["terms.seats"],
      seat_billing: fields["terms.seat_billing"],
      enrollment: fields["terms.enrollment"],
      enrollment_domain: fields["terms.enrollment_domain"]
    }
  end

  @doc """
  JSON-safe form of a compiled plan that `parse/1` reads back unchanged, so
  read models never recompile a contract from defaults (ADR-098).
  """
  def serialize(%__MODULE__{} = plan) do
    %{
      compiled: true,
      entitlement_version: plan.version,
      package_type: plan.package_type,
      channels: plan.channels |> MapSet.to_list() |> Enum.sort(),
      capabilities: plan.capabilities |> MapSet.to_list() |> Enum.sort(),
      allowances:
        Map.new(plan.allowances, fn {key, config} ->
          {key, %{limit: config.limit, period: config.period}}
        end),
      class_type_scope: serialize_scope(plan.class_type_scope),
      location_scope: serialize_scope(plan.location_scope),
      time_windows: plan.time_windows,
      terms: plan.terms
    }
  end

  defp serialize_scope(:all), do: "all"
  defp serialize_scope(scope), do: scope |> MapSet.to_list() |> Enum.sort()

  defp parse_compiled(params) do
    allowances = value(params, "allowances", %{})

    with {:ok, channels} <- parse_enum_set(value(params, "channels", []), @channels, :channel),
         {:ok, capabilities} <-
           parse_enum_set(value(params, "capabilities", []), @capabilities, :capability),
         {:ok, allowances} <- parse_compiled_allowances(allowances) do
      {:ok,
       %__MODULE__{
         version: value(params, "entitlement_version", 2),
         package_type: value(params, "package_type"),
         channels: channels,
         capabilities: capabilities,
         allowances: allowances,
         class_type_scope: class_type_scope(value(params, "class_type_scope", "all")),
         location_scope: class_type_scope(value(params, "location_scope", "all")),
         time_windows: value(params, "time_windows", []),
         terms: atomize_terms(value(params, "terms", %{}))
       }}
    end
  end

  # Class-type allowances keep their string keys; named allowances are atoms.
  defp parse_compiled_allowances(allowances) when is_map(allowances) do
    Enum.reduce_while(allowances, {:ok, %{}}, fn {key, config}, {:ok, acc} ->
      name = to_string(key)

      allowance =
        if class_type_allowance_key?(name), do: name, else: known_atom(name, @allowances)

      with false <- is_nil(allowance),
           {:ok, normalized} <- parse_allowance(name, config) do
        {:cont, {:ok, Map.put(acc, allowance, normalized)}}
      else
        true -> {:halt, {:error, {:unknown_allowance, name}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_compiled_allowances(_), do: {:error, :invalid_entitlement_plan}

  @term_keys ~w[
    booking_window_days cancellation_cutoff_hours waitlist_priority no_show_penalty_waived
    rollover_max freeze_days_per_year member_discount_percent member_discount_scope
    minimum_commitment_months joining_fee_cents validity_starts expiry_reminder_days validity
    auto_renew response_sla_hours pt_format pt_group_size pt_session_minutes pt_coach_id
    compatible_package_ids beneficiaries quota_sharing allow_minor_beneficiaries seats
    seat_billing enrollment enrollment_domain
  ]a

  defp atomize_terms(terms) when is_map(terms) do
    Enum.reduce(@term_keys, %{}, fn key, acc ->
      case Map.fetch(terms, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> Map.put(acc, key, Map.get(terms, Atom.to_string(key)))
      end
    end)
  end

  defp atomize_terms(_terms), do: %{}

  @doc """
  One plan for everything a member holds today (ADR-098): access and scopes are
  the union of all plans; allowances and terms come from the first plan that
  defines them, so the primary subscription wins. Reservations still pick the
  subscription that pays.
  """
  def merge([]), do: nil
  def merge([plan]), do: plan

  def merge([primary | rest]) do
    Enum.reduce(rest, primary, fn plan, acc ->
      %{
        acc
        | channels: MapSet.union(acc.channels, plan.channels),
          capabilities: MapSet.union(acc.capabilities, plan.capabilities),
          allowances: Map.merge(plan.allowances, acc.allowances),
          class_type_scope: union_scope(acc.class_type_scope, plan.class_type_scope),
          location_scope: union_scope(acc.location_scope, plan.location_scope),
          time_windows: union_windows(acc.time_windows, plan.time_windows),
          terms: Map.merge(plan.terms, acc.terms, fn _key, theirs, ours -> ours || theirs end)
      }
    end)
  end

  defp union_scope(:all, _other), do: :all
  defp union_scope(_scope, :all), do: :all
  defp union_scope(left, right), do: MapSet.union(left, right)

  # No windows means any time, so it wins over restricted hours.
  defp union_windows([], _other), do: []
  defp union_windows(_windows, []), do: []
  defp union_windows(left, right), do: Enum.uniq(left ++ right)

  @doc "Whether a local weekday (1 = Monday) and time fall inside the plan's allowed windows."
  def within_time_windows?(%__MODULE__{time_windows: []}, _weekday, _time), do: true
  def within_time_windows?(_plan, nil, _time), do: true

  def within_time_windows?(%__MODULE__{time_windows: windows}, weekday, %Time{} = time) do
    Enum.any?(windows, fn %{"days" => days, "from" => from, "to" => to} ->
      weekday in days and
        Time.compare(time, Time.from_iso8601!(from <> ":00")) != :lt and
        Time.compare(time, Time.from_iso8601!(to <> ":00")) == :lt
    end)
  end

  def location_included?(%__MODULE__{location_scope: :all}, _location_id), do: true
  def location_included?(_plan, nil), do: true

  def location_included?(%__MODULE__{location_scope: scope}, location_id),
    do: MapSet.member?(scope, location_id)

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
