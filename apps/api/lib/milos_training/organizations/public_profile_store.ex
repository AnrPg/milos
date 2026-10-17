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
end
