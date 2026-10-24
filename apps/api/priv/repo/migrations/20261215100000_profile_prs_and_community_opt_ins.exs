defmodule Palee.Repo.Migrations.ProfilePrsAndCommunityOptIns do
  @moduledoc """
  ADR-196 (Εγώ › PRs and Κοινοποίηση & ορατότητα):

  1. `user_pr_records.profile_audience`: who sees a PR on the owner's
     profile, apart from coaches (ADR-139 ladder) and explicit grantees
     (ADR-129). `private` (the default, vision §4.5) or `followers`. Followers
     read it through `user_pr_records_follower_read_policy`: the reader's own
     active follow of the owner admits the row, so no definer is needed.
  2. Two community opt-ins on `user_gamification_preferences`:
     `pr_celebrations` (an automatic card in the club when a PR falls, off
     until the member turns it on) and `challenge_rankings` (appear in
     challenge rankings, on as today). Rankings list other members, whose
     preference rows are owner-only, so `palee_hides_challenge_rankings`
     answers that one boolean as a definer.
  """

  use Ecto.Migration

  def up do
    alter table(:user_pr_records) do
      add :profile_audience, :string, null: false, default: "private"
    end

    create constraint(:user_pr_records, :user_pr_records_profile_audience_check,
             check: "profile_audience IN ('private', 'followers')"
           )

    execute("""
    CREATE POLICY user_pr_records_follower_read_policy ON user_pr_records
    FOR SELECT
    USING (
      profile_audience = 'followers'
      AND EXISTS (
        SELECT 1
        FROM public.community_follows f
        WHERE f.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND f.target_type = 'user'
          AND f.target_id = user_pr_records.user_id
          AND f.status = 'active'
      )
    )
    """)

    alter table(:user_gamification_preferences) do
      add :pr_celebrations, :boolean, null: false, default: false
      add :challenge_rankings, :boolean, null: false, default: true
    end

    execute("""
    CREATE OR REPLACE FUNCTION palee_hides_challenge_rankings(member_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1
        FROM public.user_gamification_preferences prefs
        WHERE prefs.user_id = member_id
          AND prefs.challenge_rankings = false
      )
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_hides_challenge_rankings(uuid)")

    alter table(:user_gamification_preferences) do
      remove :challenge_rankings
      remove :pr_celebrations
    end

    execute("DROP POLICY IF EXISTS user_pr_records_follower_read_policy ON user_pr_records")
    drop constraint(:user_pr_records, :user_pr_records_profile_audience_check)

    alter table(:user_pr_records) do
      remove :profile_audience
    end
  end
end
