defmodule MilosTraining.Body.BodyStore do
  @moduledoc """
  Facade over the configured Body adapter (ADR-158). Every call runs inside
  a `RepoContext` session: the person's own for their body data, a coach's
  tenant session for shared reads.
  """

  @behaviour MilosTraining.Body.Ports.BodyStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :body_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_snapshots(context, user_id, opts),
    do: scoped(context, :list_snapshots, [user_id, opts])

  @impl true
  def get_snapshot(context, user_id, id, opts),
    do: scoped(context, :get_snapshot, [user_id, id, opts])

  @impl true
  def create_snapshot(context, attrs), do: scoped(context, :create_snapshot, [attrs])

  @impl true
  def update_snapshot(context, user_id, id, attrs),
    do: scoped(context, :update_snapshot, [user_id, id, attrs])

  @impl true
  def delete_snapshot(context, user_id, id), do: scoped(context, :delete_snapshot, [user_id, id])

  @impl true
  def delete_empty_snapshots(context, user_id),
    do: scoped(context, :delete_empty_snapshots, [user_id])

  @impl true
  def list_metric_points(context, user_id, key, since, opts \\ []),
    do: scoped(context, :list_metric_points, [user_id, key, since, opts])

  @impl true
  def latest_taken_at(context, user_id), do: scoped(context, :latest_taken_at, [user_id])

  @impl true
  def list_photos(context, snapshot_ids), do: scoped(context, :list_photos, [snapshot_ids])

  @impl true
  def insert_photo(context, attrs), do: scoped(context, :insert_photo, [attrs])

  @impl true
  def get_photo(context, user_id, photo_id), do: scoped(context, :get_photo, [user_id, photo_id])

  @impl true
  def delete_photo(context, user_id, photo_id),
    do: scoped(context, :delete_photo, [user_id, photo_id])

  @impl true
  def refresh_photo(context, media_id, attrs),
    do: scoped(context, :refresh_photo, [media_id, attrs])

  @impl true
  def latest_photos(context, user_id), do: scoped(context, :latest_photos, [user_id])

  @impl true
  def get_settings(context, user_id), do: scoped(context, :get_settings, [user_id])

  @impl true
  def put_settings(context, user_id, changes),
    do: scoped(context, :put_settings, [user_id, changes])

  @impl true
  def list_consents(context, user_id), do: scoped(context, :list_consents, [user_id])

  @impl true
  def grant_consent(context, user_id, scope, now),
    do: scoped(context, :grant_consent, [user_id, scope, now])

  @impl true
  def withdraw_consent(context, user_id, scope, now),
    do: scoped(context, :withdraw_consent, [user_id, scope, now])

  @impl true
  def photos_consented?(context, user_id), do: scoped(context, :photos_consented?, [user_id])

  @impl true
  def record_access(context, attrs), do: scoped(context, :record_access, [attrs])

  @impl true
  def list_access_log(context, user_id, limit),
    do: scoped(context, :list_access_log, [user_id, limit])

  # A definer lookup across people: ids only, no session needed.
  @impl true
  def reminders_due(now, limit), do: adapter().reminders_due(now, limit)

  @impl true
  def mark_reminded(context, user_id, now), do: scoped(context, :mark_reminded, [user_id, now])
end
