defmodule MilosTraining.Repo.Migrations.BookingSharingWithFollowers do
  use Ecto.Migration

  # ADR-142 decision 12 (P2-M2, board 5 Q6): the «Φίλοι» chip in Πρόγραμμα
  # shows the classes people you follow are going to. Bookings are private
  # by default (vision §4.5), so each person opts in, once, for all their
  # followers. community_social_settings is account-scoped and only its
  # owner reads it; followers learn only who among the people they follow
  # shares, through a SECURITY DEFINER helper bound to the session's account.

  def up do
    create table(:community_social_settings, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :share_bookings, :boolean, null: false, default: false
      # When the member answered the one-time offer (or set it themselves).
      add :share_bookings_offered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY community_social_settings_owner_policy ON community_social_settings
    FOR ALL USING (#{owner}) WITH CHECK (#{owner})
    """)

    execute("ALTER TABLE community_social_settings ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE community_social_settings FORCE ROW LEVEL SECURITY")

    # The people the session's account actively follows who share their
    # bookings with followers. Nothing else about anyone's settings leaks.
    execute("""
    CREATE OR REPLACE FUNCTION milos_booking_sharers()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT f.target_id
      FROM public.community_follows f
      JOIN public.community_social_settings s ON s.user_id = f.target_id
      WHERE f.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        AND f.target_type = 'user'
        AND f.status = 'active'
        AND s.share_bookings
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_booking_sharers()")
    drop table(:community_social_settings)
  end
end
