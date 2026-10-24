defmodule Palee.Repo.Migrations.CreateGuideProgress do
  @moduledoc """
  ADR-193: how far a person got in each in-app walkthrough (shop, events,
  offers, own club and event), so a guide is offered once, resumes where it
  was left and shows as done on every device. Personal data: owner-only RLS.
  """

  use Ecto.Migration

  def change do
    create table(:guide_progress, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :guide_id, :string, primary_key: true
      add :version, :integer, null: false
      add :status, :string, null: false
      add :step, :integer, null: false, default: 0
      add :runs, :integer, null: false, default: 1
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:guide_progress, :guide_progress_status_check,
             check: "status IN ('started', 'completed', 'dismissed')"
           )

    create constraint(:guide_progress, :guide_progress_bounds_check,
             check:
               "guide_id ~ '^[a-z][a-z0-9_]{1,47}$' AND version BETWEEN 1 AND 1000 " <>
                 "AND step BETWEEN 0 AND 99 AND runs >= 1"
           )

    execute(
      """
      CREATE POLICY guide_progress_owner_policy ON guide_progress
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS guide_progress_owner_policy ON guide_progress"
    )

    execute(
      "ALTER TABLE guide_progress ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE guide_progress DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE guide_progress FORCE ROW LEVEL SECURITY",
      "ALTER TABLE guide_progress NO FORCE ROW LEVEL SECURITY"
    )
  end
end
