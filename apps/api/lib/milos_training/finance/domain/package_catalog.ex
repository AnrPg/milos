defmodule MilosTraining.Finance.Domain.PackageCatalog do
  @moduledoc """
  Closed catalog of every package contract field (entitlement catalog v2).

  Each field has a flat dotted key, a section, a value kind, kind-specific
  constraints and the delivery phase that implements it. Values are stored as
  JSON-compatible terms so subscription snapshots can be compared and rendered
  without atoms created from customer input.

  Fields whose phase is not implemented exist so every package stores a
  complete contract, but they cannot deviate from their type preset until the
  owning phase ships enforcement and product surfaces.
  """

  @implemented_phases [:a, :b]

  # Phase C fields ship feature by feature (ADR-098); each becomes authorable
  # once its enforcement exists. Emptied when the phase completes.
  @released_ahead ~w[
    content.on_demand_video content.advanced_analytics
    online_coaching.form_reviews online_coaching.response_sla_hours online_coaching.nutrition_plan
    personal_training.included personal_training.sessions personal_training.format
    personal_training.group_size personal_training.session_minutes personal_training.coach_id
    personal_training.assessments
  ]

  @quota_periods ["calendar_week", "calendar_month", "subscription_period"]
  @duration_units ["day", "week", "month"]
  @amenities ["sauna", "locker", "towel", "parking", "childcare"]
  @discount_scopes ["products", "personal_training", "events"]

  @fields [
    # Commercial terms
    %{key: "terms.auto_renew", section: "terms", kind: :boolean, phase: :a},
    %{key: "terms.validity", section: "terms", kind: :duration, phase: :a, max: 36},
    %{key: "terms.stacking", section: "terms", kind: :boolean, phase: :a},
    %{key: "terms.once_per_person", section: "terms", kind: :boolean, phase: :a},
    %{key: "terms.new_members_only", section: "terms", kind: :boolean, phase: :a},
    %{key: "terms.conversion_package_id", section: "terms", kind: :uuid_or_null, phase: :a},
    %{
      key: "terms.minimum_commitment_months",
      section: "terms",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 60
    },
    %{
      key: "terms.joining_fee_cents",
      section: "terms",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 10_000_000
    },
    %{
      key: "terms.validity_starts",
      section: "terms",
      kind: :enum,
      phase: :b,
      options: ["purchase", "first_use"]
    },
    %{
      key: "terms.expiry_reminder_days",
      section: "terms",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 30
    },
    %{key: "terms.compatible_package_ids", section: "terms", kind: :scope_ids, phase: :c},
    %{key: "terms.beneficiaries", section: "terms", kind: :integer, phase: :c, min: 1, max: 10},
    %{
      key: "terms.quota_sharing",
      section: "terms",
      kind: :enum,
      phase: :c,
      options: ["per_person", "shared"]
    },
    %{key: "terms.allow_minor_beneficiaries", section: "terms", kind: :boolean, phase: :c},
    %{key: "terms.seats", section: "terms", kind: :integer, phase: :c, min: 1, max: 10_000},
    %{
      key: "terms.seat_billing",
      section: "terms",
      kind: :enum,
      phase: :c,
      options: ["agreed", "used"]
    },
    %{
      key: "terms.enrollment",
      section: "terms",
      kind: :enum,
      phase: :c,
      options: ["invite_code", "email_domain"]
    },
    %{
      key: "terms.enrollment_domain",
      section: "terms",
      kind: :string_or_null,
      phase: :c,
      max: 120
    },
    # Group classes
    %{key: "group_classes.included", section: "group_classes", kind: :boolean, phase: :a},
    %{key: "group_classes.visits", section: "group_classes", kind: :quota, phase: :a},
    %{key: "group_classes.class_types", section: "group_classes", kind: :scope_ids, phase: :a},
    %{
      key: "group_classes.class_type_limits",
      section: "group_classes",
      kind: :quota_by_id,
      phase: :a
    },
    %{
      key: "group_classes.rollover_max",
      section: "group_classes",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 100
    },
    %{
      key: "group_classes.time_windows",
      section: "group_classes",
      kind: :time_windows,
      phase: :b
    },
    # Booking privileges
    %{
      key: "booking.window_days",
      section: "booking",
      kind: :gym_default_integer,
      phase: :b,
      min: 0,
      max: 365
    },
    %{
      key: "booking.waitlist_priority",
      section: "booking",
      kind: :enum,
      phase: :b,
      options: ["normal", "high"]
    },
    %{
      key: "booking.cancellation_cutoff_hours",
      section: "booking",
      kind: :gym_default_integer,
      phase: :b,
      min: 0,
      max: 168
    },
    %{key: "booking.no_show_penalty_waived", section: "booking", kind: :boolean, phase: :b},
    # Personal training
    %{key: "personal_training.included", section: "personal_training", kind: :boolean, phase: :c},
    %{key: "personal_training.sessions", section: "personal_training", kind: :quota, phase: :c},
    %{
      key: "personal_training.format",
      section: "personal_training",
      kind: :enum,
      phase: :c,
      options: ["one_to_one", "semi_private"]
    },
    %{
      key: "personal_training.group_size",
      section: "personal_training",
      kind: :integer,
      phase: :c,
      min: 1,
      max: 4
    },
    %{
      key: "personal_training.session_minutes",
      section: "personal_training",
      kind: :integer_option,
      phase: :c,
      options: [30, 45, 60, 90]
    },
    %{
      key: "personal_training.coach_id",
      section: "personal_training",
      kind: :uuid_or_null,
      phase: :c
    },
    %{
      key: "personal_training.assessments",
      section: "personal_training",
      kind: :integer,
      phase: :c,
      min: 0,
      max: 20
    },
    # Online coaching
    %{key: "online_coaching.included", section: "online_coaching", kind: :boolean, phase: :a},
    %{
      key: "online_coaching.assigned_programming",
      section: "online_coaching",
      kind: :boolean,
      phase: :a
    },
    %{key: "online_coaching.messaging", section: "online_coaching", kind: :boolean, phase: :a},
    %{key: "online_coaching.touchpoints", section: "online_coaching", kind: :quota, phase: :a},
    %{key: "online_coaching.form_reviews", section: "online_coaching", kind: :quota, phase: :c},
    %{
      key: "online_coaching.response_sla_hours",
      section: "online_coaching",
      kind: :integer_option_or_null,
      phase: :c,
      options: [24, 48, 72]
    },
    %{
      key: "online_coaching.nutrition_plan",
      section: "online_coaching",
      kind: :boolean,
      phase: :c
    },
    # Digital content
    %{key: "content.workout_library", section: "content", kind: :boolean, phase: :retired},
    %{key: "content.on_demand_video", section: "content", kind: :boolean, phase: :c},
    %{key: "content.advanced_analytics", section: "content", kind: :boolean, phase: :c},
    # Facility
    %{key: "facility.open_gym", section: "facility", kind: :boolean, phase: :b},
    %{key: "facility.open_gym_visits", section: "facility", kind: :quota, phase: :b},
    %{key: "facility.location_ids", section: "facility", kind: :scope_ids, phase: :b},
    %{
      key: "facility.amenities",
      section: "facility",
      kind: :enum_list,
      phase: :a,
      options: @amenities
    },
    %{
      key: "facility.amenities_note",
      section: "facility",
      kind: :string_or_null,
      phase: :a,
      max: 120
    },
    # Perks
    %{key: "perks.guest_passes", section: "perks", kind: :quota, phase: :b},
    %{
      key: "perks.freeze_days_per_year",
      section: "perks",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 365
    },
    %{
      key: "perks.member_discount_percent",
      section: "perks",
      kind: :integer,
      phase: :b,
      min: 0,
      max: 100
    },
    %{
      key: "perks.member_discount_scope",
      section: "perks",
      kind: :enum_list,
      phase: :b,
      options: @discount_scopes
    },
    %{key: "perks.events", section: "perks", kind: :boolean, phase: :b},
    %{key: "perks.event_visits", section: "perks", kind: :quota, phase: :b}
  ]

  @fields_by_key Map.new(@fields, &{&1.key, &1})
  @sections ~w[terms group_classes booking personal_training online_coaching content facility perks]

  def fields, do: @fields
  def keys, do: Enum.map(@fields, & &1.key)
  def sections, do: @sections
  def quota_periods, do: @quota_periods
  def implemented_phases, do: @implemented_phases

  def fetch(key) when is_binary(key) do
    case Map.fetch(@fields_by_key, key) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:unknown_package_field, key}}
    end
  end

  def fetch(key), do: {:error, {:unknown_package_field, inspect(key)}}

  def available?(%{key: key, phase: phase}),
    do: phase in @implemented_phases or key in @released_ahead

  def available?(%{phase: phase}), do: phase in @implemented_phases

  def available?(key) when is_binary(key) do
    case fetch(key) do
      {:ok, spec} -> available?(spec)
      _ -> false
    end
  end

  @doc "Validates and normalizes a single value against its field specification."
  def cast(%{kind: :boolean}, value) when is_boolean(value), do: {:ok, value}

  def cast(%{kind: :integer} = spec, value) when is_integer(value),
    do: within(spec, value)

  def cast(%{kind: :gym_default_integer}, nil), do: {:ok, nil}

  def cast(%{kind: :gym_default_integer} = spec, value) when is_integer(value),
    do: within(spec, value)

  def cast(%{kind: :integer_option, options: options}, value) when is_integer(value),
    do: if(value in options, do: {:ok, value}, else: {:error, :invalid_option})

  def cast(%{kind: :integer_option_or_null}, nil), do: {:ok, nil}

  def cast(%{kind: :integer_option_or_null, options: options}, value) when is_integer(value),
    do: if(value in options, do: {:ok, value}, else: {:error, :invalid_option})

  def cast(%{kind: :enum, options: options}, value) when is_binary(value),
    do: if(value in options, do: {:ok, value}, else: {:error, :invalid_option})

  def cast(%{kind: :enum_list, options: options}, values) when is_list(values) do
    if Enum.all?(values, &(&1 in options)),
      do: {:ok, values |> Enum.uniq() |> Enum.sort()},
      else: {:error, :invalid_option}
  end

  def cast(%{kind: :string_or_null}, nil), do: {:ok, nil}

  def cast(%{kind: :string_or_null, max: max}, value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> {:ok, nil}
      String.length(trimmed) > max -> {:error, :too_long}
      true -> {:ok, trimmed}
    end
  end

  def cast(%{kind: :uuid_or_null}, nil), do: {:ok, nil}

  def cast(%{kind: :uuid_or_null}, value) when is_binary(value), do: cast_uuid(value)

  def cast(%{kind: :scope_ids}, "all"), do: {:ok, "all"}

  def cast(%{kind: :scope_ids}, values) when is_list(values) and values != [] do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case is_binary(value) && cast_uuid(value) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        _ -> {:halt, {:error, :invalid_id}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  def cast(%{kind: :quota}, value) when is_map(value), do: cast_quota(value)

  def cast(%{kind: :quota_by_id}, values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      with true <- is_map(entry),
           {:ok, id} <- cast_uuid(get(entry, "id")),
           {:ok, quota} <- cast_quota(entry),
           true <- is_integer(quota["limit"]) || {:error, :limited_quota_required} do
        {:cont, {:ok, [Map.put(quota, "id", id) | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        _ -> {:halt, {:error, :invalid_quota}}
      end
    end)
    |> case do
      {:ok, entries} ->
        entries = Enum.sort_by(entries, & &1["id"])
        ids = Enum.map(entries, & &1["id"])

        if length(Enum.uniq(ids)) == length(ids),
          do: {:ok, entries},
          else: {:error, :duplicate_id}

      error ->
        error
    end
  end

  def cast(%{kind: :duration}, nil), do: {:ok, nil}

  def cast(%{kind: :duration, max: max}, value) when is_map(value) do
    amount = get(value, "amount")
    unit = get(value, "unit")

    cond do
      unit not in @duration_units -> {:error, :invalid_duration}
      not is_integer(amount) or amount < 1 -> {:error, :invalid_duration}
      months(amount, unit) > max -> {:error, :out_of_range}
      true -> {:ok, %{"amount" => amount, "unit" => unit}}
    end
  end

  def cast(%{kind: :time_windows}, values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn window, {:ok, acc} ->
      case cast_time_window(window) do
        {:ok, window} -> {:cont, {:ok, [window | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, windows} -> {:ok, Enum.reverse(windows)}
      error -> error
    end
  end

  def cast(_spec, _value), do: {:error, :invalid_value}

  @doc "Adds a package duration to an inclusive start date and returns the inclusive end date."
  def duration_end(%Date{} = starts_on, %{"amount" => amount, "unit" => "day"}),
    do: Date.add(starts_on, amount - 1)

  def duration_end(%Date{} = starts_on, %{"amount" => amount, "unit" => "week"}),
    do: Date.add(starts_on, amount * 7 - 1)

  def duration_end(%Date{} = starts_on, %{"amount" => amount, "unit" => "month"}),
    do: starts_on |> Date.shift(month: amount) |> Date.add(-1)

  defp within(spec, value) do
    min = Map.get(spec, :min, value)
    max = Map.get(spec, :max, value)
    if value >= min and value <= max, do: {:ok, value}, else: {:error, :out_of_range}
  end

  defp cast_quota(value) do
    limit = get(value, "limit")
    period = get(value, "period")

    cond do
      period not in @quota_periods ->
        {:error, :invalid_quota_period}

      limit == "unlimited" ->
        {:ok, %{"limit" => "unlimited", "period" => period}}

      is_integer(limit) and limit >= 0 and limit <= 10_000 ->
        {:ok, %{"limit" => limit, "period" => period}}

      true ->
        {:error, :invalid_quota_limit}
    end
  end

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end

  defp cast_uuid(_), do: {:error, :invalid_id}

  defp cast_time_window(window) when is_map(window) do
    days = get(window, "days")
    from = get(window, "from")
    to = get(window, "to")

    with true <- is_list(days) and days != [] and Enum.all?(days, &(&1 in 1..7)),
         {:ok, from_time} <- parse_time(from),
         {:ok, to_time} <- parse_time(to),
         :lt <- Time.compare(from_time, to_time) do
      {:ok, %{"days" => days |> Enum.uniq() |> Enum.sort(), "from" => from, "to" => to}}
    else
      _ -> {:error, :invalid_time_window}
    end
  end

  defp cast_time_window(_), do: {:error, :invalid_time_window}

  defp parse_time(value) when is_binary(value) and byte_size(value) == 5,
    do: Time.from_iso8601(value <> ":00")

  defp parse_time(_), do: {:error, :invalid_time}

  defp months(amount, "month"), do: amount
  defp months(amount, "week"), do: div(amount * 7, 30)
  defp months(amount, "day"), do: div(amount, 30)

  defp get(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))
end
