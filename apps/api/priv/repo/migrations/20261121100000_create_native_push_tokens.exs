defmodule MilosTraining.Repo.Migrations.CreateNativePushTokens do
  @moduledoc """
  ADR-171 (P3-M9, native wrapper): push tokens of the store apps, next to the
  browser's `push_subscriptions`.

  One row per app install: `provider` `fcm` (Android, Firebase Cloud
  Messaging) or `apns` (iOS), the device token, the platform, the app id it
  was issued for and, for APNs, the environment (`production` or `sandbox`).
  A token belongs to whoever signed in on that install last: registering it
  again under another account moves it (`milos_claim_native_push_token`),
  since the person who signed in is the one holding the phone.

  The person's own rows (personal-session RLS, like `push_subscriptions`).
  """

  use Ecto.Migration

  def up do
    create table(:native_push_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :platform, :string, null: false
      add :token, :text, null: false
      add :app_id, :string
      add :app_version, :string
      add :apns_environment, :string
      add :last_registered_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:native_push_tokens, :native_push_tokens_provider_check,
             check:
               "(provider = 'fcm' AND platform = 'android' AND apns_environment IS NULL) OR " <>
                 "(provider = 'apns' AND platform = 'ios' AND " <>
                 "apns_environment IN ('production', 'sandbox'))"
           )

    create constraint(:native_push_tokens, :native_push_tokens_token_check,
             check: "char_length(token) BETWEEN 16 AND 4096"
           )

    create unique_index(:native_push_tokens, [:provider, :token])
    create index(:native_push_tokens, [:user_id])

    execute("""
    CREATE POLICY native_push_tokens_owner_policy ON native_push_tokens
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE native_push_tokens ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE native_push_tokens FORCE ROW LEVEL SECURITY")

    # The install's token moves to the account that registers it now. Only the
    # session person can claim, and only for themselves; nothing is returned.
    execute("""
    CREATE FUNCTION milos_claim_native_push_token(p_provider text, p_token text)
    RETURNS integer
    LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH removed AS (
        DELETE FROM public.native_push_tokens t
        WHERE t.provider = p_provider
          AND t.token = p_token
          AND NULLIF(current_setting('app.user_id', true), '') IS NOT NULL
          AND t.user_id <> NULLIF(current_setting('app.user_id', true), '')::uuid
        RETURNING 1
      )
      SELECT count(*)::integer FROM removed
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_claim_native_push_token(text, text)")
    drop table(:native_push_tokens)
  end
end
