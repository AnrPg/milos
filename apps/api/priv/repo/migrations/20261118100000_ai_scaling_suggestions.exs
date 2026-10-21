defmodule MilosTraining.Repo.Migrations.AiScalingSuggestions do
  @moduledoc """
  ADR-174 (P3-M12): AI scaling suggestions.

  `organization_ai_settings` is the gym's one AI settings row (AiUsage
  context, next to the `ai_usage_records` meter): the gym's own provider key,
  encrypted at rest (`DataCipher`, the same AES-GCM envelope as device tokens,
  ADR-161), its last four characters for display, whether the provider has
  rejected it, an optional model override and the scaling switch, off by
  default. The key is write-only over the API.

  `scaling_suggestions` (Scaling context) holds one advisor answer per
  athlete and assignment: per-movement changes with reasons, a suggested
  scale level, and the coach's decision. Only an approved row carries
  `modifications` (ADR-050 patch shape) and only an approved row is ever read
  by the member. A partial unique index keeps one live row per athlete and
  assignment; replaced rows become `superseded`.

  Both are tenant tables (forced RLS, tenant trigger, purged with the gym).
  """

  use Ecto.Migration

  def up do
    create table(:organization_ai_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :provider, :text, null: false, default: "anthropic"
      add :api_key, :binary
      add :api_key_last4, :text
      add :key_status, :text, null: false, default: "unknown"
      add :key_checked_at, :utc_datetime_usec
      add :model, :text
      add :scaling_enabled, :boolean, null: false, default: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_ai_settings, [:organization_id])

    create constraint(:organization_ai_settings, :organization_ai_settings_values_check,
             check: """
             provider IN ('anthropic')
             AND key_status IN ('unknown', 'valid', 'rejected')
             AND (model IS NULL OR char_length(model) BETWEEN 3 AND 80)
             AND (api_key_last4 IS NULL OR char_length(api_key_last4) <= 4)
             """
           )

    create table(:scaling_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :athlete_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # Workouts-owned rows, plain ids (no cross-context keys).
      add :assigned_workout_id, :binary_id, null: false
      add :master_workout_id, :binary_id, null: false
      add :scheduled_for, :date, null: false
      add :status, :text, null: false, default: "pending"
      add :summary, :text
      add :scale_level_slug, :text
      add :items, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :modifications, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :injury_regions, {:array, :text}, null: false, default: []
      add :input_digest, :text, null: false
      add :provider, :text
      add :model, :text
      add :operation_id, :binary_id
      add :coach_note, :text
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:scaling_suggestions, [:assigned_workout_id, :athlete_id],
             where: "status IN ('pending', 'approved', 'dismissed', 'no_change')",
             name: :scaling_suggestions_live_index
           )

    create index(:scaling_suggestions, [:organization_id, :status, :scheduled_for])
    create index(:scaling_suggestions, [:organization_id, :athlete_id, :master_workout_id])

    create constraint(:scaling_suggestions, :scaling_suggestions_values_check,
             check: """
             status IN ('pending', 'approved', 'dismissed', 'no_change', 'superseded')
             AND jsonb_typeof(items) = 'array'
             AND jsonb_typeof(modifications) = 'array'
             AND (summary IS NULL OR char_length(summary) <= 600)
             AND (coach_note IS NULL OR char_length(coach_note) <= 500)
             """
           )

    for table <- ~w(organization_ai_settings scaling_suggestions) do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    drop table(:scaling_suggestions)
    drop table(:organization_ai_settings)
  end
end
