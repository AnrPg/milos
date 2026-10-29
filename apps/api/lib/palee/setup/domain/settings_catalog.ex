defmodule Palee.Setup.Domain.SettingsCatalog do
  @moduledoc """
  Every business setting the API exposes, with the CP-H1 verdict
  (`docs/plans/v3-settings-audit.md`, ADR-255):

    * `:basic` – stays on the main settings screen;
    * `:advanced` – under «Προχωρημένα», closed by default;
    * `:derive` – the app or a setup recipe sets it; editable under «Προχωρημένα»;
    * `:remove` – no owner should see it (the code keeps it).

  A setting is advanced (hidden by default) unless its verdict is `:basic`.
  `recipe: true` marks the settings a setup recipe may set; the section and
  field say which application service writes it. Nothing here is deleted
  from the code: the catalog only labels.
  """

  @verdicts [:basic, :advanced, :derive, :remove]

  # {key, verdict, default, recipe?}; the key is "<section>.<field>".
  @entries [
    # A. Organization
    {"organization.timezone", :derive, "UTC", false},
    {"organization.default_locale", :derive, "en", false},
    {"organization.invitation_lifetime_seconds", :remove, 604_800, false},
    {"branding.brand_name", :basic, nil, false},
    {"branding.logo", :basic, nil, false},
    {"branding.primary_color", :derive, nil, false},
    {"provider.kind", :derive, "gym", true},
    {"access.role_grants", :advanced, %{}, true},
    {"join_link.member", :basic, false, false},
    {"join_link.athlete", :advanced, false, false},
    {"workouts.wod_goals_visible_by_default", :advanced, false, true},
    {"workouts.wod_assistant_enabled", :advanced, true, true},
    {"onboarding.checklist", :derive, nil, false},
    # B. Money
    {"finance.document_mode", :derive, "invoice", false},
    {"finance.package_modules", :derive, ["group_classes", "online_coaching"], true},
    {"finance.subscription_grace_days", :advanced, 3, true},
    {"finance.subscription_expiry_reminder_days", :advanced, 5, true},
    {"finance.payment_reminder_interval_days", :advanced, 7, true},
    {"finance.entitlement_enforcement_mode", :remove, "observe", false},
    {"finance.entitlement_timezone", :derive, "Europe/Athens", false},
    # C. Class booking rules
    {"scheduling.default_capacity", :basic, 12, true},
    {"scheduling.default_auto_approve", :basic, false, true},
    {"scheduling.default_cancellation_cutoff_minutes", :basic, nil, true},
    {"scheduling.default_booking_window_days", :advanced, nil, true},
    {"scheduling.default_booking_timeout_minutes", :advanced, 60, true},
    # D. Streaks and leaderboard
    {"gamification.leaderboard_enabled", :basic, true, true},
    {"gamification.streak_shields", :advanced, 1, true},
    {"gamification.streak_shield_reset_day", :advanced, nil, false},
    # E. Check-in
    {"check_in.window_before_minutes", :advanced, 30, true},
    {"check_in.window_after_minutes", :advanced, 15, true},
    {"check_in.open_gym_requires_package", :derive, true, true},
    {"check_in.visitor_trial_offer", :advanced, true, true},
    {"check_in.desk_override", :advanced, false, true},
    {"check_in.door_rotation_seconds", :remove, 30, false},
    {"check_in.member_code_mode", :advanced, "rotating", false},
    {"check_in.geofence_reminder", :advanced, true, false},
    # F. Community
    {"community.member_groups", :advanced, "approval", true},
    {"community.partners_enabled", :advanced, true, true},
    # G. Trial visitors
    {"trials.enabled", :basic, false, true},
    {"trials.seats_per_class", :basic, 2, true},
    {"trials.bring_note", :basic, nil, false},
    {"trials.approval", :advanced, "auto", true},
    {"trials.weekly_limit", :advanced, nil, false},
    {"trials.per_person_limit", :advanced, 1, false},
    {"trials.class_type_ids", :advanced, [], false},
    {"trials.horizon_days", :advanced, nil, false},
    {"trials.first_timers_only", :advanced, false, false},
    {"trials.no_show_consumes", :advanced, false, false},
    {"trials.conversion_package_id", :derive, nil, true},
    # H. AI
    {"ai.api_key", :advanced, nil, false},
    {"ai.model", :remove, nil, false},
    {"ai.scaling_enabled", :advanced, false, false},
    {"ai.voice_enabled", :advanced, false, false},
    # I. «Φέρε φίλο»
    {"referrals.active", :basic, true, false},
    {"referrals.reward", :basic, "manual", false},
    {"referrals.friend_reward", :basic, "none", false},
    {"referrals.qualifying_stage", :advanced, "paid", false},
    {"referrals.attribution_days", :advanced, 30, false},
    {"referrals.yearly_cap", :advanced, nil, false},
    {"referrals.approval", :advanced, "manual", false},
    # J. Per class type
    {"class_type.name", :basic, nil, false},
    {"class_type.kind", :basic, "class", false},
    {"class_type.level", :advanced, "all_levels", false},
    {"class_type.audiences", :advanced, [], false},
    {"class_type.credit_cost", :advanced, 1, false},
    # L. Legal identity and payments
    {"fiscal.identity", :basic, nil, false},
    {"fiscal.authority_connection", :advanced, nil, false},
    {"payments.account", :basic, nil, false}
  ]

  @by_key Map.new(@entries, fn {key, _verdict, _default, _recipe} = entry -> {key, entry} end)

  def verdicts, do: @verdicts

  @doc "Every setting as a map, in catalog order."
  def all, do: Enum.map(@entries, &to_map/1)

  @doc "The setting under `key`, or nil."
  def fetch(key) do
    case Map.fetch(@by_key, key) do
      {:ok, entry} -> {:ok, to_map(entry)}
      :error -> :error
    end
  end

  @doc "Whether the web hides the setting until «Προχωρημένα» is opened."
  def advanced?(key) do
    case Map.fetch(@by_key, key) do
      {:ok, {_key, verdict, _default, _recipe}} -> verdict != :basic
      :error -> true
    end
  end

  @doc "Keys of every advanced setting, sorted."
  def advanced_keys,
    do: @entries |> Enum.map(&elem(&1, 0)) |> Enum.filter(&advanced?/1) |> Enum.sort()

  @doc "Whether a setup recipe may set `key`."
  def recipe_settable?(key) do
    case Map.fetch(@by_key, key) do
      {:ok, {_key, _verdict, _default, recipe?}} -> recipe?
      :error -> false
    end
  end

  @doc "`%{verdict => count}` for every verdict."
  def counts do
    base = Map.new(@verdicts, &{&1, 0})

    Enum.reduce(@entries, base, fn {_key, verdict, _default, _recipe}, acc ->
      Map.update!(acc, verdict, &(&1 + 1))
    end)
  end

  @doc "Splits `\"section.field\"` into `{section, field}`."
  def split(key) do
    [section, field] = String.split(key, ".", parts: 2)
    {section, field}
  end

  defp to_map({key, verdict, default, recipe?}) do
    {section, field} = split(key)

    %{
      key: key,
      section: section,
      field: field,
      verdict: verdict,
      advanced: verdict != :basic,
      default: default,
      set_by_recipe: recipe?
    }
  end
end
