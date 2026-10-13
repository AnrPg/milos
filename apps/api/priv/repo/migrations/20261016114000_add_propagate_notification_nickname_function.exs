defmodule MilosTraining.Repo.Migrations.AddPropagateNotificationNicknameFunction do
  use Ecto.Migration

  # TD-092 / ADR-131: after a nickname change, PropagateNicknameJob rewrites the
  # sender/athlete nickname snapshotted into other users' notification
  # payloads. Notifications are owner-only under RLS, so the job's UPDATE (no
  # session scope, and the rows belong to many recipients) matched nothing
  # under the production runtime role.
  #
  # This SECURITY DEFINER function performs exactly that rewrite and only for
  # a real rename: the new nickname must belong to an account and the old one
  # to none (nicknames are unique), so it cannot be used to relabel another
  # live account's messages.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_propagate_notification_nickname(old_nickname text, new_nickname text)
    RETURNS integer
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      sender_rows integer := 0;
      athlete_rows integer := 0;
    BEGIN
      IF old_nickname IS NULL OR new_nickname IS NULL OR old_nickname = new_nickname THEN
        RETURN 0;
      END IF;

      IF NOT EXISTS (SELECT 1 FROM public.users WHERE nickname = new_nickname)
         OR EXISTS (SELECT 1 FROM public.users WHERE nickname = old_nickname) THEN
        RETURN 0;
      END IF;

      UPDATE public.notifications
         SET payload = jsonb_set(payload, '{sender_nickname}', to_jsonb(new_nickname))
       WHERE payload->>'sender_nickname' = old_nickname;
      GET DIAGNOSTICS sender_rows = ROW_COUNT;

      UPDATE public.notifications
         SET payload = jsonb_set(payload, '{athlete_nickname}', to_jsonb(new_nickname))
       WHERE payload->>'athlete_nickname' = old_nickname;
      GET DIAGNOSTICS athlete_rows = ROW_COUNT;

      RETURN sender_rows + athlete_rows;
    END
    $$
    """)

    # EXECUTE stays with PUBLIC (the default), like the other milos_*
    # SECURITY DEFINER helpers.
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_propagate_notification_nickname(text, text)")
  end
end
