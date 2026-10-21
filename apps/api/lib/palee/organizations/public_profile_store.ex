defmodule Palee.Organizations.PublicProfileStore do
  @moduledoc "Facade over the public profile adapter; every call runs in the gym's `RepoContext` session (ADR-142)."

  @behaviour Palee.Organizations.Ports.PublicProfileStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :public_profile_store)

  @impl true
  def get(context), do: RepoContext.run(context, fn -> adapter().get(context) end)

  @impl true
  def upsert(context, params),
    do: RepoContext.run(context, fn -> adapter().upsert(context, params) end)

  @impl true
  def create_suggestion(context, params),
    do: RepoContext.run(context, fn -> adapter().create_suggestion(context, params) end)

  # Platform review: the adapter reads across gyms through a narrow SQL function.
  @impl true
  def pending_suggestions, do: adapter().pending_suggestions()

  @impl true
  def resolve_suggestion(id, status), do: adapter().resolve_suggestion(id, status)

  # Visitors: narrow SQL functions that only answer for published gyms.
  @impl true
  def public_box_by_slug(slug), do: adapter().public_box_by_slug(slug)

  @impl true
  def public_boxes(organization_ids), do: adapter().public_boxes(organization_ids)
end
