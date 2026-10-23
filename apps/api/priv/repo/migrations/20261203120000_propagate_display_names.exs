defmodule Palee.Repo.Migrations.PropagateDisplayNames do
  use Ecto.Migration

  # ADR-187: notifications snapshot the sender's display name, which is no
  # longer the unique handle. The rename guard now looks at display names: the
  # new name must belong to a profile and the old one to none, so a name
  # another profile still uses is never relabelled.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_propagate_notification_nickname(old_nickname text, new_nickname text)
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

      IF NOT EXISTS (SELECT 1 FROM public.users WHERE display_nickname = new_nickname)
         OR EXISTS (SELECT 1 FROM public.users WHERE display_nickname = old_nickname) THEN
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
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION palee_propagate_notification_nickname(old_nickname text, new_nickname text)
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
  end
end
