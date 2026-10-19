defmodule MilosTraining.Identity.SavedFilterStore do
  @moduledoc "Facade over the saved-filter adapter; every call runs in the person's `RepoContext` session (ADR-151)."

  @behaviour MilosTraining.Identity.Ports.SavedFilterStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :saved_filter_store)

  defp run(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def list(context, surface), do: run(context, :list, [surface])
  @impl true
  def put_last_used(context, surface, params, at),
    do: run(context, :put_last_used, [surface, params, at])

  @impl true
  def put_named(context, surface, name, params, at),
    do: run(context, :put_named, [surface, name, params, at])

  @impl true
  def count_named(context, surface), do: run(context, :count_named, [surface])
  @impl true
  def delete_named(context, id), do: run(context, :delete_named, [id])
end
