defmodule MilosTraining.Finance.Domain.PackagePresets do
  @moduledoc """
  Complete per-type presets and type-enforced (locked) values (ADR-096).

  A preset holds a value for every catalog field. A lock pins either a whole
  field or one key of a map-valued field (for example
  `group_classes.visits.period`) because that value defines the package type.
  Every lock carries a stable reason code that clients localize.
  """

  alias MilosTraining.Finance.Domain.{PackageCatalog, PackageType}

  @base %{
    "terms.auto_renew" => true,
    "terms.validity" => nil,
    "terms.stacking" => false,
    "terms.once_per_person" => false,
    "terms.new_members_only" => false,
    "terms.conversion_package_id" => nil,
    "terms.minimum_commitment_months" => 0,
    "terms.joining_fee_cents" => 0,
    "terms.validity_starts" => "purchase",
    "terms.expiry_reminder_days" => 0,
    "terms.compatible_package_ids" => "all",
    "terms.beneficiaries" => 1,
    "terms.quota_sharing" => "per_person",
    "terms.allow_minor_beneficiaries" => false,
    "terms.seats" => 1,
    "terms.seat_billing" => "agreed",
    "terms.enrollment" => "invite_code",
    "terms.enrollment_domain" => nil,
    "group_classes.included" => true,
    "group_classes.visits" => %{"limit" => "unlimited", "period" => "calendar_month"},
    "group_classes.class_types" => "all",
    "group_classes.class_type_limits" => [],
    "group_classes.rollover_max" => 0,
    "group_classes.time_windows" => [],
    "booking.window_days" => nil,
    "booking.waitlist_priority" => "normal",
    "booking.cancellation_cutoff_hours" => nil,
    "booking.no_show_penalty_waived" => false,
    "personal_training.included" => false,
    "personal_training.sessions" => %{"limit" => 0, "period" => "subscription_period"},
    "personal_training.format" => "one_to_one",
    "personal_training.group_size" => 1,
    "personal_training.session_minutes" => 60,
    "personal_training.coach_id" => nil,
    "personal_training.assessments" => 0,
    "online_coaching.included" => false,
    "online_coaching.assigned_programming" => true,
    "online_coaching.messaging" => true,
    "online_coaching.touchpoints" => %{"limit" => "unlimited", "period" => "calendar_month"},
    "online_coaching.form_reviews" => %{"limit" => 0, "period" => "calendar_month"},
    "online_coaching.response_sla_hours" => nil,
    "online_coaching.nutrition_plan" => false,
    "content.workout_library" => false,
    "content.on_demand_video" => false,
    "content.advanced_analytics" => false,
    "facility.open_gym" => false,
    "facility.open_gym_visits" => %{"limit" => "unlimited", "period" => "calendar_month"},
    "facility.location_ids" => "all",
    "facility.amenities" => [],
    "facility.amenities_note" => nil,
    "perks.guest_passes" => %{"limit" => 0, "period" => "calendar_month"},
    "perks.freeze_days_per_year" => 0,
    "perks.member_discount_percent" => 0,
    "perks.member_discount_scope" => [],
    "perks.events" => false,
    "perks.event_visits" => %{"limit" => 0, "period" => "calendar_month"}
  }

  @whole_validity "subscription_period"

  @overrides %{
    "membership" => %{},
    "class_pack" => %{
      "terms.auto_renew" => false,
      "terms.validity" => %{"amount" => 3, "unit" => "month"},
      "terms.stacking" => true,
      "group_classes.visits" => %{"limit" => 10, "period" => @whole_validity}
    },
    "drop_in" => %{
      "terms.auto_renew" => false,
      "terms.validity" => %{"amount" => 30, "unit" => "day"},
      "terms.stacking" => true,
      "group_classes.visits" => %{"limit" => 1, "period" => @whole_validity}
    },
    "trial" => %{
      "terms.auto_renew" => false,
      "terms.validity" => %{"amount" => 7, "unit" => "day"},
      "terms.once_per_person" => true,
      "terms.new_members_only" => true,
      "terms.expiry_reminder_days" => 2,
      "group_classes.visits" => %{"limit" => "unlimited", "period" => @whole_validity},
      "booking.no_show_penalty_waived" => true,
      "facility.open_gym" => true,
      "facility.open_gym_visits" => %{"limit" => "unlimited", "period" => @whole_validity},
      "personal_training.assessments" => 1
    },
    "pt_pack" => %{
      "terms.auto_renew" => false,
      "terms.validity" => %{"amount" => 3, "unit" => "month"},
      "terms.stacking" => true,
      "group_classes.included" => false,
      "personal_training.included" => true,
      "personal_training.sessions" => %{"limit" => 10, "period" => @whole_validity},
      "personal_training.assessments" => 1,
      "online_coaching.included" => true,
      "online_coaching.assigned_programming" => false
    },
    "add_on" => %{
      "terms.auto_renew" => false,
      "group_classes.included" => false
    },
    "shared" => %{
      "terms.beneficiaries" => 2
    },
    "corporate" => %{
      "terms.minimum_commitment_months" => 12,
      "terms.seats" => 10
    }
  }

  @freeze_days_by_period %{
    "quarterly" => 7,
    "semiannual" => 14,
    "annual" => 30
  }

  @recurring_locks [
    {"terms.validity", nil, "recurring_type"},
    {"terms.stacking", false, "recurring_type"}
  ]

  @one_off_locks [
    {"terms.auto_renew", false, "one_off_type"},
    {"terms.minimum_commitment_months", 0, "one_off_type"}
  ]

  @locks %{
    "membership" => @recurring_locks,
    "shared" => @recurring_locks,
    "corporate" => @recurring_locks,
    "class_pack" =>
      @one_off_locks ++
        [
          {"group_classes.included", true, "type_service"},
          {"group_classes.visits.period", @whole_validity, "counts_whole_validity"}
        ],
    "drop_in" =>
      @one_off_locks ++
        [
          {"group_classes.included", true, "type_service"},
          {"group_classes.visits.limit", 1, "single_visit"},
          {"group_classes.visits.period", @whole_validity, "counts_whole_validity"},
          {"group_classes.class_type_limits", [], "single_visit"},
          {"perks.guest_passes.limit", 0, "single_visit"},
          {"perks.freeze_days_per_year", 0, "single_visit"}
        ],
    "trial" =>
      @one_off_locks ++
        [
          {"terms.once_per_person", true, "trial_once"},
          {"terms.joining_fee_cents", 0, "trial_once"},
          {"group_classes.visits.period", @whole_validity, "counts_whole_validity"},
          {"perks.guest_passes.limit", 0, "trial_once"},
          {"perks.freeze_days_per_year", 0, "trial_once"}
        ],
    "pt_pack" =>
      @one_off_locks ++
        [
          {"personal_training.included", true, "type_service"},
          {"personal_training.sessions.period", @whole_validity, "counts_whole_validity"}
        ],
    "add_on" => [
      {"terms.auto_renew", false, "follows_base"},
      {"terms.validity", nil, "follows_base"},
      {"terms.stacking", false, "follows_base"},
      {"terms.minimum_commitment_months", 0, "follows_base"},
      {"terms.joining_fee_cents", 0, "follows_base"},
      {"perks.freeze_days_per_year", 0, "follows_base"},
      {"facility.location_ids", "all", "follows_base"}
    ]
  }

  @doc "Complete preset field map for a package type and billing period."
  def preset(type_key, billing_period \\ nil) do
    with {:ok, type} <- PackageType.fetch(type_key) do
      billing_period = billing_period || PackageType.default_billing_period(type)

      fields =
        @base
        |> Map.merge(Map.fetch!(@overrides, type_key))
        |> apply_billing_period(type_key, billing_period)

      {:ok, fields}
    end
  end

  @doc "Preset overrides that depend on the chosen billing period."
  def billing_period_overrides(type_key) when type_key in ["membership", "shared"] do
    Map.new(PackageType.billing_periods(%{billing_model: "recurring"}), fn period ->
      {period, %{"perks.freeze_days_per_year" => Map.get(@freeze_days_by_period, period, 0)}}
    end)
  end

  def billing_period_overrides(_type_key), do: %{}

  @doc "Type-enforced values as `{path, value, reason}` tuples."
  def locks(type_key), do: Map.get(@locks, type_key, [])

  @doc "Returns the locked value for a whole field or a map key inside it."
  def locked_value(field_value, path) do
    case String.split(path, ".") do
      [_, _] -> field_value
      [_, _, sub_key] when is_map(field_value) -> Map.get(field_value, sub_key)
      _ -> nil
    end
  end

  @doc "Field key that a lock path belongs to."
  def lock_field(path) do
    case String.split(path, ".") do
      [section, name | _] -> section <> "." <> name
    end
  end

  def locked_paths(type_key), do: Enum.map(locks(type_key), &elem(&1, 0))

  def field_locked?(type_key, field_key),
    do: Enum.any?(locks(type_key), fn {path, _, _} -> lock_field(path) == field_key end)

  @doc false
  def base, do: @base

  @doc false
  def assert_complete! do
    missing = PackageCatalog.keys() -- Map.keys(@base)
    extra = Map.keys(@base) -- PackageCatalog.keys()
    if missing != [] or extra != [], do: raise("preset mismatch: #{inspect({missing, extra})}")
    :ok
  end

  defp apply_billing_period(fields, type_key, billing_period) do
    case Map.get(billing_period_overrides(type_key), billing_period) do
      nil -> fields
      overrides -> Map.merge(fields, overrides)
    end
  end
end
