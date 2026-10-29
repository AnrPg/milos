defmodule Palee.Repo.Migrations.CreateExecutionPlanSets do
  @moduledoc """
  ADR-270: what an athlete did in each set / round of a structured plan
  section, prescribed next to actual, keyed by the plan row id and its place
  in the run so planned-vs-done joins back to `workout_sections.plan`.

  Owner rows like their parent `workout_executions`: the owner writes them;
  anyone who can read the parent execution (the owner, the tenant's staff, a
  coach it is shared with) can read them.
  """
  use Ecto.Migration

  @user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  # The owner's own row, on an execution of its own.
  @owner_write """
  user_id = #{@user}
  AND EXISTS (
    SELECT 1 FROM workout_executions e
    WHERE e.id = execution_plan_sets.execution_id AND e.user_id = execution_plan_sets.user_id
  )
  """

  def up do
    create table(:execution_plan_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:workout_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :organization_id, :binary_id
      add :master_workout_id, :binary_id
      add :section_id, :binary_id, null: false
      add :row_id, :string, size: 200, null: false
      add :exercise_name, :string, size: 200, null: false, default: ""
      add :exercise_ref, :string, size: 200
      add :block_index, :integer, null: false
      add :round_index, :integer, null: false
      add :part_index, :integer, null: false, default: 0
      add :phase_index, :integer, null: false, default: 0
      add :interrupt, :boolean, null: false, default: false
      add :prescribed_reps_text, :string, size: 200, null: false, default: ""
      add :prescribed_load_text, :string, size: 200, null: false, default: ""
      add :prescribed_reps, :decimal, precision: 10, scale: 2
      add :prescribed_load_kg, :decimal, precision: 10, scale: 2
      add :prescribed_load_pct, :decimal, precision: 10, scale: 2
      add :one_rep_max_kg, :decimal, precision: 10, scale: 2
      add :actual_reps, :decimal, precision: 10, scale: 2
      add :actual_load_kg, :decimal, precision: 10, scale: 2
      add :logged, :boolean, null: false, default: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(
             :execution_plan_sets,
             [
               :execution_id,
               :section_id,
               :row_id,
               :interrupt,
               :block_index,
               :round_index,
               :part_index,
               :phase_index
             ],
             name: :execution_plan_sets_place_index
           )

    create index(:execution_plan_sets, [:user_id, :exercise_ref])
    create index(:execution_plan_sets, [:organization_id])

    create constraint(:execution_plan_sets, :execution_plan_sets_indexes_check,
             check:
               "block_index >= -1 AND block_index < 12 AND round_index >= 1 AND " <>
                 "part_index >= 0 AND phase_index >= 0 AND (interrupt = (block_index = -1))"
           )

    create constraint(:execution_plan_sets, :execution_plan_sets_numbers_check,
             check:
               "coalesce(prescribed_reps, 0) >= 0 AND coalesce(prescribed_load_kg, 0) >= 0 AND " <>
                 "coalesce(prescribed_load_pct, 0) >= 0 AND coalesce(one_rep_max_kg, 0) >= 0 AND " <>
                 "coalesce(actual_reps, 0) >= 0 AND coalesce(actual_load_kg, 0) >= 0"
           )

    execute("ALTER TABLE execution_plan_sets ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE execution_plan_sets FORCE ROW LEVEL SECURITY")

    # Read: whoever can read the parent execution (its own policies apply in
    # the subquery). Write (insert, update, delete): only the owner, on an
    # execution of its own. Split per command so a scope that may only read
    # the parent (staff, a coach it is shared with) cannot delete or change
    # the actuals: a FOR ALL policy's USING would let it, as WITH CHECK is
    # never evaluated for DELETE.
    execute("""
    CREATE POLICY execution_plan_sets_read_policy ON execution_plan_sets
      FOR SELECT
      USING (
        user_id = #{@user}
        OR EXISTS (
          SELECT 1 FROM workout_executions e WHERE e.id = execution_plan_sets.execution_id
        )
      )
    """)

    execute("""
    CREATE POLICY execution_plan_sets_owner_insert_policy ON execution_plan_sets
      FOR INSERT
      WITH CHECK (#{@owner_write})
    """)

    execute("""
    CREATE POLICY execution_plan_sets_owner_update_policy ON execution_plan_sets
      FOR UPDATE
      USING (user_id = #{@user})
      WITH CHECK (#{@owner_write})
    """)

    execute("""
    CREATE POLICY execution_plan_sets_owner_delete_policy ON execution_plan_sets
      FOR DELETE
      USING (user_id = #{@user})
    """)
  end

  def down do
    drop table(:execution_plan_sets)
  end
end
