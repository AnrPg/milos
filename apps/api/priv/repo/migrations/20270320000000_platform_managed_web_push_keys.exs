defmodule Palee.Repo.Migrations.PlatformManagedWebPushKeys do
  @moduledoc """
  ADR-275: the server makes the Web Push key pair itself and keeps the private
  key encrypted (`DataCipher`), so nobody pastes or sees keys again.

  * `notification_push_settings` becomes a real singleton (unique `singleton`
    column), so two API replicas booting at once cannot each insert a pair.
  * The plaintext `vapid_private_key` column is dropped and the public key
    cleared: the keys made by hand were shown on screen, so the first start
    after this migration makes a fresh pair.
  * Browser subscriptions made with the old public key can never be delivered
    again, so they are removed; each device subscribes again with the new key
    the next time its owner opens Palee (permission already granted, no prompt).
  * Two SECURITY DEFINER functions give the platform console what RLS hides
    from it (subscriptions are personal rows): the device count with the last
    successful delivery, and removing every browser subscription when the
    keys are replaced. Both answer only to an active vendor.
  """

  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM notification_push_settings
    WHERE id NOT IN (
      SELECT id FROM notification_push_settings ORDER BY updated_at DESC LIMIT 1
    )
    """)

    alter table(:notification_push_settings) do
      add :singleton, :boolean, null: false, default: true
      add :vapid_private_key_encrypted, :binary
      add :keys_created_at, :utc_datetime_usec
      remove :vapid_private_key, :text
    end

    create constraint(:notification_push_settings, :notification_push_settings_singleton_check,
             check: "singleton"
           )

    create unique_index(:notification_push_settings, [:singleton])

    execute("UPDATE notification_push_settings SET vapid_public_key = NULL")
    execute("DELETE FROM push_subscriptions")

    create index(:push_dispatch_attempts, [:completed_at],
             where: "status = 'sent'",
             name: :push_dispatch_attempts_sent_completed_at_index
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_web_push_device_stats()
    RETURNS TABLE(device_count bigint, last_sent_at timestamp)
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF NOT public.palee_acting_user_is_vendor() THEN
        RAISE EXCEPTION 'vendor required' USING ERRCODE = 'insufficient_privilege';
      END IF;

      RETURN QUERY
      SELECT
        (SELECT count(*) FROM public.push_subscriptions),
        (SELECT max(completed_at) FROM public.push_dispatch_attempts WHERE status = 'sent');
    END;
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_forget_web_push_devices()
    RETURNS bigint
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      removed bigint;
    BEGIN
      IF NOT public.palee_acting_user_is_vendor() THEN
        RAISE EXCEPTION 'vendor required' USING ERRCODE = 'insufficient_privilege';
      END IF;

      DELETE FROM public.push_subscriptions;
      GET DIAGNOSTICS removed = ROW_COUNT;
      RETURN removed;
    END;
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_forget_web_push_devices()")
    execute("DROP FUNCTION IF EXISTS palee_web_push_device_stats()")

    drop_if_exists index(:push_dispatch_attempts, [:completed_at],
                     name: :push_dispatch_attempts_sent_completed_at_index
                   )

    drop_if_exists unique_index(:notification_push_settings, [:singleton])

    drop_if_exists constraint(
                     :notification_push_settings,
                     :notification_push_settings_singleton_check
                   )

    alter table(:notification_push_settings) do
      add :vapid_private_key, :text
      remove :keys_created_at
      remove :vapid_private_key_encrypted
      remove :singleton
    end
  end
end
