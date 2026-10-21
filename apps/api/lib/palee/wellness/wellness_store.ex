defmodule Palee.Wellness.WellnessStore do
  @moduledoc "Dispatches the Wellness persistence port to the configured adapter."

  @behaviour Palee.Wellness.Ports.WellnessStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def insert_entry(attrs), do: adapter().insert_entry(attrs)
  @impl true
  def upsert_device_entry(attrs), do: adapter().upsert_device_entry(attrs)
  @impl true
  def get_entry(id, user_id), do: adapter().get_entry(id, user_id)
  @impl true
  def change_entry(entry, attrs, now), do: adapter().change_entry(entry, attrs, now)
  @impl true
  def set_entry_visibility(entry, rung), do: adapter().set_entry_visibility(entry, rung)
  @impl true
  def delete_entry(entry, now), do: adapter().delete_entry(entry, now)
  @impl true
  def list_entries(user_id, from, to), do: adapter().list_entries(user_id, from, to)

  @impl true
  def list_day_items(user_id, bound, limit, scope),
    do: adapter().list_day_items(user_id, bound, limit, scope)

  @impl true
  def list_craving_items(user_id, bound, limit, scope),
    do: adapter().list_craving_items(user_id, bound, limit, scope)

  @impl true
  def insert_craving(attrs), do: adapter().insert_craving(attrs)
  @impl true
  def get_craving(id, user_id), do: adapter().get_craving(id, user_id)
  @impl true
  def change_craving(craving, attrs), do: adapter().change_craving(craving, attrs)
  @impl true
  def set_craving_visibility(craving, rung), do: adapter().set_craving_visibility(craving, rung)
  @impl true
  def delete_craving(craving, now), do: adapter().delete_craving(craving, now)
  @impl true
  def list_cravings(user_id, from, to), do: adapter().list_cravings(user_id, from, to)
  @impl true
  def craving_follow_ups_due(now, limit), do: adapter().craving_follow_ups_due(now, limit)
  @impl true
  def mark_followed_up(craving, at), do: adapter().mark_followed_up(craving, at)

  @impl true
  def get_preferences(user_id), do: adapter().get_preferences(user_id)
  @impl true
  def put_preferences(user_id, attrs), do: adapter().put_preferences(user_id, attrs)
  @impl true
  def water_reminders_due(now, limit), do: adapter().water_reminders_due(now, limit)
  @impl true
  def mark_water_reminded(user_id, day), do: adapter().mark_water_reminded(user_id, day)

  @impl true
  def export(user_id, sections), do: adapter().export(user_id, sections)
  @impl true
  def erase(user_id, sections, now), do: adapter().erase(user_id, sections, now)
  @impl true
  def transaction(fun), do: adapter().transaction(fun)

  defp adapter do
    Application.get_env(
      :palee,
      :wellness_store,
      Palee.Infrastructure.Wellness.EctoWellnessStore
    )
  end
end
