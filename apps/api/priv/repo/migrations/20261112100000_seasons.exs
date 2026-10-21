defmodule Palee.Repo.Migrations.Seasons do
  @moduledoc """
  ADR-167 (P3-M5): seasons, fixed-length programmes a gym sells (Hyrox prep,
  a 12-week challenge).

  `season_offerings` is the gym's product: dates, capacity, price, the
  programme (an ordered list of `{day, workout_id}`), its coaches and an
  optional membership package whose entitlements a confirmed participant
  receives. `season_enrollments` is one member's request and its outcome;
  one row per member and season, re-used when they ask again.

  Both are tenant tables (the gym's scope, like packages and trials). Member
  routes run in the gym's scope too, so the bare tenant policy covers them.

  `assigned_workouts.season_offering_id` labels the programme's workouts. It
  is a plain id (no cross-context key, like `source_scheduled_class_id`), and
  joins the uniqueness key so a season workout never merges into a personal
  assignment of the same workout on the same day.
  """

  use Ecto.Migration

  @season_notification_types ~w(season_requested season_confirmed season_declined season_cancelled)

  def up do
    create table(:season_offerings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :title, :text, null: false
      add :description, :text
      add :welcome_message, :text
      add :starts_on, :date, null: false
      add :weeks, :integer, null: false
      add :capacity, :integer, null: false
      add :price_cents, :integer, null: false, default: 0
      add :currency, :text, null: false, default: "EUR"

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :nilify_all)

      add :programme, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :coach_ids, {:array, :binary_id}, null: false, default: []
      add :status, :text, null: false, default: "draft"
      # The #season channel in the gym's club (Community owns it), a plain id.
      add :channel_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:season_offerings, [:organization_id, :status, :starts_on])

    create constraint(:season_offerings, :season_offerings_status_check,
             check: "status IN ('draft', 'published', 'running', 'completed', 'cancelled')"
           )

    create constraint(:season_offerings, :season_offerings_limits_check,
             check: """
             char_length(title) BETWEEN 2 AND 80
             AND (description IS NULL OR char_length(description) <= 2000)
             AND (welcome_message IS NULL OR char_length(welcome_message) <= 1000)
             AND weeks BETWEEN 1 AND 52
             AND capacity BETWEEN 1 AND 500
             AND price_cents >= 0
             """
           )

    create constraint(:season_offerings, :season_offerings_programme_check,
             check: "jsonb_typeof(programme) = 'array'"
           )

    create table(:season_enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :season_offering_id,
          references(:season_offerings, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false
      add :requested_at, :utc_datetime_usec, null: false
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decline_reason, :text
      add :cancelled_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      # The Finance subscription a confirmation created, a plain id.
      add :package_subscription_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:season_enrollments, [:season_offering_id, :user_id])
    create index(:season_enrollments, [:organization_id, :status])
    create index(:season_enrollments, [:organization_id, :user_id])

    create constraint(:season_enrollments, :season_enrollments_status_check,
             check:
               "status IN ('requested', 'waitlisted', 'active', 'declined', 'cancelled', 'completed')"
           )

    create constraint(:season_enrollments, :season_enrollments_reason_check,
             check: "decline_reason IS NULL OR char_length(decline_reason) <= 300"
           )

    for table <- ~w(season_offerings season_enrollments) do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    alter table(:assigned_workouts) do
      add :season_offering_id, :uuid
    end

    create index(:assigned_workouts, [:organization_id, :season_offering_id],
             where: "season_offering_id IS NOT NULL",
             name: :assigned_workouts_season_offering_index
           )

    drop_if_exists(
      unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :instructions],
        name: :assigned_workouts_workout_date_notes_index
      )
    )

    create unique_index(
             :assigned_workouts,
             [:master_workout_id, :scheduled_for, :instructions, :season_offering_id],
             name: :assigned_workouts_workout_date_notes_index,
             nulls_distinct: false
           )

    add_notification_types(@season_notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@season_notification_types)})")
    remove_notification_types(@season_notification_types)

    drop_if_exists(
      unique_index(
        :assigned_workouts,
        [:master_workout_id, :scheduled_for, :instructions, :season_offering_id],
        name: :assigned_workouts_workout_date_notes_index
      )
    )

    execute("DELETE FROM assigned_workouts WHERE season_offering_id IS NOT NULL")

    create unique_index(:assigned_workouts, [:master_workout_id, :scheduled_for, :instructions],
             name: :assigned_workouts_workout_date_notes_index,
             nulls_distinct: false
           )

    drop index(:assigned_workouts, [:organization_id, :season_offering_id],
           name: :assigned_workouts_season_offering_index
         )

    alter table(:assigned_workouts) do
      remove :season_offering_id
    end

    drop table(:season_enrollments)
    drop table(:season_offerings)
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
