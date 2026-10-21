defmodule Palee.Wellness do
  @moduledoc """
  Wellness bounded context (ADR-159; vision §7.7, §8.6; mockups 21–22): the
  «Σήμερα» card of Ημερολόγιο › Ευεξία. Water, sleep and meals are entries of
  a kind with a validated value; Λιγούρα is its own entry; the member's
  targets live in their preferences. All of it is account data, private by
  default, with optional gym provenance. Πώς νιώθω (mood, stress) and
  injuries stay in Wellbeing; the coach's plan stays in Nutrition.
  """

  alias Palee.Wellness.Domain.{
    CravingPolicy,
    DaySummary,
    EntryKinds,
    LocalDay,
    Meal,
    PreferencesPolicy
  }

  alias Palee.Wellness.{Preferences, WellnessStore}

  defdelegate with_context(context, fun), to: WellnessStore

  # Domain.
  defdelegate kinds(), to: EntryKinds
  defdelegate sources(), to: EntryKinds
  defdelegate device_sources(), to: EntryKinds
  defdelegate cast_value(kind, params), to: EntryKinds, as: :cast
  defdelegate counts_at(kind, value, occurred_at), to: EntryKinds
  defdelegate local_day(at, zone), to: LocalDay, as: :of
  defdelegate valid_zone?(zone), to: LocalDay
  defdelegate parse_window(from, to), to: LocalDay
  defdelegate days_between(from, to), to: LocalDay, as: :range
  defdelegate craving_triggers(), to: CravingPolicy, as: :triggers
  defdelegate craving_outcomes(), to: CravingPolicy, as: :outcomes
  defdelegate normalize_craving_triggers(triggers), to: CravingPolicy, as: :normalize_triggers
  defdelegate craving_follow_up_at(outcome, now), to: CravingPolicy, as: :follow_up_at
  defdelegate meal_slots(), to: Meal, as: :slots
  defdelegate meal_plan_fits(), to: Meal, as: :plan_fits
  defdelegate meal_portions(), to: Meal, as: :portion_keys
  defdelegate meal_media_id(value), to: Meal, as: :media_id
  defdelegate preference_items(), to: PreferencesPolicy, as: :items
  defdelegate ordered_items(item_order), to: PreferencesPolicy
  defdelegate summarize_days(dates, entries, cravings, moods, prefs), to: DaySummary, as: :build
  defdelegate week_line(days), to: DaySummary

  # Entries.
  defdelegate insert_entry(attrs), to: WellnessStore
  defdelegate upsert_device_entry(attrs), to: WellnessStore
  defdelegate get_entry(id, user_id), to: WellnessStore
  defdelegate change_entry(entry, attrs, now), to: WellnessStore
  defdelegate set_entry_visibility(entry, rung), to: WellnessStore
  defdelegate delete_entry(entry, now), to: WellnessStore
  defdelegate list_entries(user_id, from, to), to: WellnessStore

  # Cravings.
  defdelegate list_day_items(user_id, bound, limit, scope), to: WellnessStore
  defdelegate list_craving_items(user_id, bound, limit, scope), to: WellnessStore
  defdelegate insert_craving(attrs), to: WellnessStore
  defdelegate get_craving(id, user_id), to: WellnessStore
  defdelegate change_craving(craving, attrs), to: WellnessStore
  defdelegate set_craving_visibility(craving, rung), to: WellnessStore
  defdelegate delete_craving(craving, now), to: WellnessStore
  defdelegate list_cravings(user_id, from, to), to: WellnessStore
  defdelegate craving_follow_ups_due(now, limit), to: WellnessStore
  defdelegate mark_followed_up(craving, at), to: WellnessStore

  # Preferences: the stored row, or the defaults for someone who never set any.
  def preferences(user_id) do
    WellnessStore.get_preferences(user_id) ||
      struct(Preferences, Map.put(PreferencesPolicy.defaults(), :user_id, user_id))
  end

  defdelegate put_preferences(user_id, attrs), to: WellnessStore
  defdelegate water_reminders_due(now, limit), to: WellnessStore
  defdelegate mark_water_reminded(user_id, day), to: WellnessStore

  @sections ~w(wellness cravings)
  def erasable_sections, do: @sections
  defdelegate export(user_id, sections), to: WellnessStore
  defdelegate erase(user_id, sections, now), to: WellnessStore
  defdelegate transaction(fun), to: WellnessStore

  # ADR-117 reviewed tenant export/purge of rows with gym provenance.
  def tenant_data_policy, do: Palee.Wellness.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
