defmodule Palee.Devices.DeviceStore do
  @moduledoc "Dispatches the Devices persistence port to the configured adapter."

  @behaviour Palee.Devices.Ports.DeviceStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def get_connection(user_id, provider), do: adapter().get_connection(user_id, provider)
  @impl true
  def insert_connection(attrs), do: adapter().insert_connection(attrs)
  @impl true
  def update_connection(connection, attrs), do: adapter().update_connection(connection, attrs)
  @impl true
  def list_connections(user_id), do: adapter().list_connections(user_id)

  @impl true
  def oauth_state_lookup(state_hash), do: adapter().oauth_state_lookup(state_hash)
  @impl true
  def provider_users_lookup(provider, ids), do: adapter().provider_users_lookup(provider, ids)
  @impl true
  def refresh_due_lookup(before, limit), do: adapter().refresh_due_lookup(before, limit)

  @impl true
  def get_import(user_id, provider, kind, provider_id),
    do: adapter().get_import(user_id, provider, kind, provider_id)

  @impl true
  def get_import_by_id(id, user_id), do: adapter().get_import_by_id(id, user_id)
  @impl true
  def insert_import(attrs), do: adapter().insert_import(attrs)
  @impl true
  def update_import(import, attrs), do: adapter().update_import(import, attrs)
  @impl true
  def list_imports_since(user_id, since), do: adapter().list_imports_since(user_id, since)
  @impl true
  def list_imports(user_id, provider), do: adapter().list_imports(user_id, provider)
  @impl true
  def delete_imports(user_id, provider), do: adapter().delete_imports(user_id, provider)

  @impl true
  def insert_activity(attrs), do: adapter().insert_activity(attrs)
  @impl true
  def update_activity(activity, attrs), do: adapter().update_activity(activity, attrs)
  @impl true
  def get_activity(id, user_id), do: adapter().get_activity(id, user_id)
  @impl true
  def list_pending_activities(user_id), do: adapter().list_pending_activities(user_id)

  @impl true
  def list_activity_items(user_id, bound, limit, scope),
    do: adapter().list_activity_items(user_id, bound, limit, scope)

  @impl true
  def list_merged(kind, ids), do: adapter().list_merged(kind, ids)
  @impl true
  def match_candidates(from, to), do: adapter().match_candidates(from, to)

  @impl true
  def list_activities_between(user_id, from, to),
    do: adapter().list_activities_between(user_id, from, to)

  @impl true
  def list_activities(user_id), do: adapter().list_activities(user_id)
  @impl true
  def delete_activities(user_id, provider), do: adapter().delete_activities(user_id, provider)

  @impl true
  def upsert_daily_stat(attrs), do: adapter().upsert_daily_stat(attrs)
  @impl true
  def list_daily_stats(user_id, from, to), do: adapter().list_daily_stats(user_id, from, to)
  @impl true
  def list_all_daily_stats(user_id), do: adapter().list_all_daily_stats(user_id)
  @impl true
  def delete_daily_stats(user_id, source), do: adapter().delete_daily_stats(user_id, source)

  @impl true
  def transaction(fun), do: adapter().transaction(fun)

  defp adapter do
    Application.get_env(
      :palee,
      :device_store,
      Palee.Infrastructure.Devices.EctoDeviceStore
    )
  end
end
