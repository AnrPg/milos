defmodule Palee.Media.MediaStore do
  @moduledoc """
  Facade over the configured Media adapter. Every call runs inside a
  `RepoContext` session: the gym's scope for tenant media, the person's
  session for account media (ADR-148).
  """

  @behaviour Palee.Media.Ports.MediaStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :media_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def create(context, scope, attrs), do: scoped(context, :create, [scope, attrs])
  @impl true
  def get(context, scope, id), do: scoped(context, :get, [scope, id])
  @impl true
  def list(context, scope, ids), do: scoped(context, :list, [scope, ids])
  @impl true
  def mark_ready(context, scope, id, attrs), do: scoped(context, :mark_ready, [scope, id, attrs])

  @impl true
  def mark_processing(context, scope, id, attrs),
    do: scoped(context, :mark_processing, [scope, id, attrs])

  @impl true
  def mark_processed(context, scope, id, attrs),
    do: scoped(context, :mark_processed, [scope, id, attrs])

  @impl true
  def mark_rejected(context, scope, id, reason),
    do: scoped(context, :mark_rejected, [scope, id, reason])

  @impl true
  def set_attached(context, scope, ids, at), do: scoped(context, :set_attached, [scope, ids, at])

  @impl true
  def attach(context, scope, ids, attachment, at),
    do: scoped(context, :attach, [scope, ids, attachment, at])

  @impl true
  def update_alt_text(context, scope, id, text),
    do: scoped(context, :update_alt_text, [scope, id, text])

  @impl true
  def usage(context, scope, since), do: scoped(context, :usage, [scope, since])
  @impl true
  def delete(context, scope, ids), do: scoped(context, :delete, [scope, ids])
  @impl true
  def list_unattached(context, scope, before),
    do: scoped(context, :list_unattached, [scope, before])

  @impl true
  def list_ids_by_purpose(context, scope, purpose),
    do: scoped(context, :list_ids_by_purpose, [scope, purpose])

  # Answered by narrow SECURITY DEFINER functions, outside any session.
  @impl true
  def account_orphan_owner_ids(before), do: adapter().account_orphan_owner_ids(before)
  @impl true
  def dangling_post_media(before, limit), do: adapter().dangling_post_media(before, limit)
  @impl true
  def stale_post_media(before, limit), do: adapter().stale_post_media(before, limit)
end
