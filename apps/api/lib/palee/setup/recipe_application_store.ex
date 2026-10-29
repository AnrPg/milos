defmodule Palee.Setup.RecipeApplicationStore do
  @moduledoc false
  @behaviour Palee.Setup.Ports.RecipeApplicationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :setup_recipe_application_store)

  @impl true
  def transaction(context, fun),
    do: RepoContext.run(context, fn -> adapter().transaction(context, fun) end)

  @impl true
  def insert(context, attrs),
    do: RepoContext.run(context, fn -> adapter().insert(context, attrs) end)

  @impl true
  def list(context, limit), do: RepoContext.run(context, fn -> adapter().list(context, limit) end)
end
