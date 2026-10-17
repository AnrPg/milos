defmodule MilosTraining.Repo.Migrations.CreateAiUsageRecords do
  use Ecto.Migration

  # ADR-141: one row per billed model call (Gemini today). Calls that serve one
  # user action (a free-text workout analysis is several agent calls) share an
  # operation_id. Cost is stored at the price in force when the call was made,
  # in integer nano-USD, so reports never re-price history. Append-only.
  def up do
    create table(:ai_usage_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :operation_id, :binary_id, null: false
      add :feature, :string, null: false
      add :agent, :string
      add :provider, :string, null: false
      add :model, :string, null: false
      add :model_version, :string
      add :input_tokens, :integer, null: false, default: 0
      add :cached_input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :thinking_tokens, :integer, null: false, default: 0
      add :cost_nano_usd, :bigint
      add :duration_ms, :integer
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:ai_usage_records, :ai_usage_records_tokens_check,
             check:
               "input_tokens >= 0 AND cached_input_tokens >= 0 AND output_tokens >= 0 AND thinking_tokens >= 0"
           )

    create constraint(:ai_usage_records, :ai_usage_records_cost_check,
             check: "cost_nano_usd IS NULL OR cost_nano_usd >= 0"
           )

    create index(:ai_usage_records, [:organization_id, :occurred_at])
    create index(:ai_usage_records, [:organization_id, :operation_id])
    create index(:ai_usage_records, [:organization_id, :feature, :occurred_at])

    execute("""
    CREATE TRIGGER ai_usage_records_apply_tenant_context
    BEFORE INSERT OR UPDATE ON ai_usage_records
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY ai_usage_records_tenant_policy ON ai_usage_records
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE ai_usage_records ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE ai_usage_records FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:ai_usage_records)
  end
end
