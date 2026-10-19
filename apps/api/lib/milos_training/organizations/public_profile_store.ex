defmodule MilosTraining.Organizations.PublicProfileStore do
  @moduledoc "Facade over the public profile adapter; every call runs in the gym's `RepoContext` session (ADR-142)."

  @behaviour MilosTraining.Organizations.Ports.PublicProfileStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :public_profile_store)

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
end
