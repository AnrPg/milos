defmodule Palee.Infrastructure.Setup.EctoRecipeApplicationStore do
  @moduledoc "Ecto adapter of the setup recipe application record (ADR-255)."

  @behaviour Palee.Setup.Ports.RecipeApplicationStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Setup.RecipeApplication

  @impl true
  def transaction(%{organization_id: organization_id}, fun) do
    Repo.transaction(fn ->
      # One application at a time per business (ADR-255).
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "setup_recipe:" <> organization_id
      ])

      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def insert(%{organization_id: organization_id}, attrs) do
    %RecipeApplication{organization_id: organization_id}
    |> RecipeApplication.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, to_map(row)}
      error -> error
    end
  end

  @impl true
  def list(_context, limit) do
    RecipeApplication
    |> order_by([a], desc: a.applied_at, desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  defp to_map(%RecipeApplication{} = row) do
    Map.take(row, [
      :id,
      :recipe_key,
      :recipe_version,
      :applied_by_id,
      :applied_at,
      :changes,
      :manual,
      :change_count
    ])
  end
end
