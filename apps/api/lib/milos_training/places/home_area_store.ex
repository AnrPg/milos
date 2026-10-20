defmodule MilosTraining.Places.HomeAreaStore do
  @moduledoc "Facade over the home-area adapter; every call runs in the person's `RepoContext` session (ADR-154)."

  @behaviour MilosTraining.Places.Ports.HomeAreaStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :home_area_store)

  @impl true
  def list(context), do: RepoContext.run(context, fn -> adapter().list(context) end)

  @impl true
  def replace(context, ids, now),
    do: RepoContext.run(context, fn -> adapter().replace(context, ids, now) end)
end
