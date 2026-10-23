defmodule Palee.Repo.Migrations.CoveringBranchScopes do
  @moduledoc """
  ADR-186 §8: promotions and coaching programme assignments are valid at some
  branches («Ισχύει για»), like packages (`facility.location_ids`).

  `all_locations` (default true, so every existing row keeps applying
  everywhere, future branches included) or the listed `location_ids` (1 to
  200). Ids are kept as an array, like invitation scopes: a branch archived
  later simply stops matching, and the tables keep their own RLS.
  """

  use Ecto.Migration

  @tables [:promotion_campaigns, :assigned_workouts]

  def up do
    for table <- @tables do
      alter table(table) do
        add :all_locations, :boolean, null: false, default: true
        add :location_ids, {:array, :uuid}, null: false, default: []
      end

      create constraint(table, :"#{table}_location_scope_check",
               check: "all_locations OR cardinality(location_ids) BETWEEN 1 AND 200"
             )
    end
  end

  def down do
    for table <- @tables do
      drop constraint(table, :"#{table}_location_scope_check")

      alter table(table) do
        remove :all_locations
        remove :location_ids
      end
    end
  end
end
