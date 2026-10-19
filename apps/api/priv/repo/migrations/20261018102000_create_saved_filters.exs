defmodule MilosTraining.Repo.Migrations.CreateSavedFilters do
  @moduledoc """
  ADR-151: a person's filter choices per list surface, so they follow them
  across devices: the last-used filter of each surface and named
  combinations («ΣΚ κοντά»). Personal data: owner-only RLS.
  """

  use Ecto.Migration

  def change do
    create table(:saved_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :surface, :string, null: false
      add :kind, :string, null: false
      add :name, :string
      add :params, :map, null: false, default: %{}
      add :last_used_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:saved_filters, :saved_filters_kind_check,
             check:
               "(kind = 'last_used' AND name IS NULL) OR " <>
                 "(kind = 'named' AND char_length(name) BETWEEN 1 AND 40)"
           )

    create unique_index(:saved_filters, [:user_id, :surface],
             where: "kind = 'last_used'",
             name: :saved_filters_last_used_index
           )

    create unique_index(:saved_filters, [:user_id, :surface, "lower(name)"],
             where: "kind = 'named'",
             name: :saved_filters_named_index
           )

    execute(
      """
      CREATE POLICY saved_filters_owner_policy ON saved_filters
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS saved_filters_owner_policy ON saved_filters"
    )

    execute(
      "ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE saved_filters DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE saved_filters FORCE ROW LEVEL SECURITY",
      "ALTER TABLE saved_filters NO FORCE ROW LEVEL SECURITY"
    )
  end
end
