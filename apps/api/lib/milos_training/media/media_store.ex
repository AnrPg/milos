defmodule MilosTraining.Media.MediaStore do
  @moduledoc """
  Facade over the configured Media adapter. Every call runs inside a
  `RepoContext` session: the gym's scope for tenant media, the person's
  session for account media (ADR-148).
  """

  @behaviour MilosTraining.Media.Ports.MediaStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :media_store)

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
  def set_attached(context, scope, ids, at), do: scoped(context, :set_attached, [scope, ids, at])
  @impl true
  def delete(context, scope, ids), do: scoped(context, :delete, [scope, ids])
  @impl true
  def list_unattached(context, scope, before),
    do: scoped(context, :list_unattached, [scope, before])

  # Answered by a narrow SECURITY DEFINER function, outside any session.
  @impl true
  def account_orphan_owner_ids(before), do: adapter().account_orphan_owner_ids(before)
end
