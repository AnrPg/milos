defmodule MilosTraining.Repo.Migrations.MemberReferrals do
  use Ecto.Migration

  # ADR-156 (P2-M8, board 11): members bring friends.
  #
  # 1. referral_codes: one personal code per member per box; the link and QR
  #    are milos.gr/r/<code>. Codes are unique across Milos, so the code alone
  #    finds the box, and a SECURITY DEFINER lookup tells a visitor exactly
  #    what the invite page shows (who invites, to which box), nothing more.
  # 2. referral_attributions: one row per friend per box, the funnel from the
  #    first invite to the first payment (first invite wins inside the
  #    programme's window). The Referrals context owns it; when it qualifies
  #    it opens the Finance referral event the admin already approves.
  # 3. referral_programs become two-sided and carry their own rules: the
  #    friend's gift, when an invite counts, the window, a yearly cap and
  #    manual or automatic approval. One programme is active per box.
  # 4. Notification types for the inviter (progress, reward) and staff
  #    (review), appended to whatever the constraint holds at the time, so
  #    the migration composes with other milestones' types in any order.

  @notification_types ~w(referral_progress referral_reward referral_review)

  def up do
    referral_codes()
    referral_programs()
    referral_attributions()
    policies()
    lookups()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)
    execute("DROP FUNCTION IF EXISTS milos_referral_invite(text)")
    drop table(:referral_attributions)
    drop table(:referral_codes)
    drop index(:referral_programs, [:organization_id], name: :referral_programs_one_active_index)

    for name <- ~w(friend_reward approval qualifying_stage rules)a do
      drop constraint(:referral_programs, :"referral_programs_#{name}_check")
    end

    alter table(:referral_programs) do
      remove :friend_reward_type
      remove :friend_reward_value
      remove :friend_reward_note
      remove :reward_note
      remove :qualifying_stage
      remove :attribution_days
      remove :yearly_cap
      remove :approval
    end
  end

  defp referral_codes do
    create table(:referral_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:referral_codes, [:code])

    create unique_index(:referral_codes, [:organization_id, :user_id],
             where: "revoked_at IS NULL",
             name: :referral_codes_one_active_index
           )

    create constraint(:referral_codes, :referral_codes_code_check,
             check: "code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'"
           )
  end

  defp referral_programs do
    alter table(:referral_programs) do
      # What the friend gets (board 11 Q7): free days on the first package, a
      # credit on their account, something the box describes, or nothing.
      add :friend_reward_type, :string, null: false, default: "none"
      add :friend_reward_value, :integer, null: false, default: 0
      add :friend_reward_note, :text
      # How a manual reward reads to members («Δωρεάν μπλουζάκι»).
      add :reward_note, :text
      # When an invite counts: the friend's first trial or first payment.
      add :qualifying_stage, :string, null: false, default: "paid"
      # How long an invite holds (first invite wins inside it).
      add :attribution_days, :integer, null: false, default: 60
      # Rewarded friends per member per rolling year; nil means no cap.
      add :yearly_cap, :integer
      add :approval, :string, null: false, default: "manual"
    end

    create constraint(:referral_programs, :referral_programs_friend_reward_check,
             check:
               "friend_reward_type IN ('none', 'free_days', 'credit', 'custom') AND friend_reward_value >= 0"
           )

    create constraint(:referral_programs, :referral_programs_approval_check,
             check: "approval IN ('manual', 'auto')"
           )

    create constraint(:referral_programs, :referral_programs_qualifying_stage_check,
             check: "qualifying_stage IN ('trial', 'paid')"
           )

    create constraint(:referral_programs, :referral_programs_rules_check,
             check:
               "attribution_days BETWEEN 7 AND 365 AND (yearly_cap IS NULL OR yearly_cap BETWEEN 1 AND 1000)"
           )

    # One active programme per box: keep the most recently changed one.
    execute("""
    UPDATE referral_programs p SET active = false
    WHERE p.active AND EXISTS (
      SELECT 1 FROM referral_programs q
      WHERE q.organization_id = p.organization_id AND q.active AND q.id <> p.id
        AND (q.updated_at, q.id) > (p.updated_at, p.id)
    )
    """)

    create unique_index(:referral_programs, [:organization_id],
             where: "active",
             name: :referral_programs_one_active_index
           )
  end

  defp referral_attributions do
    create table(:referral_attributions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      # The member who invited; nil once their account is gone (the friend's
      # history at the box stays).
      add :referrer_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :referred_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      # Plain ids: the code may be revoked and the event deleted while the
      # invite keeps its history.
      add :code_id, :binary_id
      add :community_event_id, :binary_id
      add :channel, :string, null: false

      # The programme the invite was made under (board 11 Q7: members keep
      # seeing the terms they invited with).
      add :referral_program_id,
          references(:referral_programs, type: :binary_id, on_delete: :nilify_all)

      # Whether the friend's account was created by this invite.
      add :new_account, :boolean, null: false, default: false
      add :attributed_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false

      # The funnel, each step stamped once.
      add :event_at, :utc_datetime_usec
      add :trial_at, :utc_datetime_usec
      add :joined_at, :utc_datetime_usec
      add :paid_at, :utc_datetime_usec

      add :status, :string, null: false, default: "open"
      add :qualified_at, :utc_datetime_usec
      add :void_reason, :text

      # The Finance referral event this invite opened when it qualified.
      add :finance_referral_event_id,
          references(:referral_events, type: :binary_id, on_delete: :nilify_all)

      # Board 11 Q7: staff apply the friend's gift on the first sale.
      add :friend_gift_applied_at, :utc_datetime_usec
      add :friend_gift_applied_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Board 11 Q4: staff can give the invite to another member, with a note.
      add :previous_referrer_user_id, :binary_id
      add :reassigned_at, :utc_datetime_usec
      add :reassigned_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:referral_attributions, [:organization_id, :referred_user_id])
    create index(:referral_attributions, [:organization_id, :referrer_user_id, :attributed_at])
    create index(:referral_attributions, [:organization_id, :status])
    create index(:referral_attributions, [:referred_user_id])
    create index(:referral_attributions, [:referrer_user_id])

    create unique_index(:referral_attributions, [:finance_referral_event_id],
             where: "finance_referral_event_id IS NOT NULL"
           )

    create constraint(:referral_attributions, :referral_attributions_channel_check,
             check: "channel IN ('link', 'qr', 'event', 'guest_pass', 'staff')"
           )

    create constraint(:referral_attributions, :referral_attributions_status_check,
             check: "status IN ('open', 'qualified', 'capped', 'expired', 'void')"
           )

    create constraint(:referral_attributions, :referral_attributions_not_self_check,
             check: "referrer_user_id IS NULL OR referrer_user_id <> referred_user_id"
           )

    create constraint(:referral_attributions, :referral_attributions_window_check,
             check: "expires_at > attributed_at"
           )
  end

  defp policies do
    org = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    me = "NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY referral_codes_tenant_policy ON referral_codes
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("""
    CREATE POLICY referral_codes_owner_read_policy ON referral_codes
    FOR SELECT USING (user_id = #{me})
    """)

    # The box handles every invite; the inviter and the friend each read their
    # own rows from their personal scope.
    execute("""
    CREATE POLICY referral_attributions_tenant_policy ON referral_attributions
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("""
    CREATE POLICY referral_attributions_party_read_policy ON referral_attributions
    FOR SELECT USING (referrer_user_id = #{me} OR referred_user_id = #{me})
    """)

    for table <- ~w(referral_codes referral_attributions) do
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  defp lookups do
    # What a visitor holding a code may know: the box (active), and who
    # invites (an active member of it). A revoked code, a former member or a
    # closed box find nothing.
    execute("""
    CREATE OR REPLACE FUNCTION milos_referral_invite(invite_code text)
    RETURNS TABLE (code_id uuid, organization_id uuid, user_id uuid, slug text, name text,
                   logo_url text, primary_color text, published boolean)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.id, c.organization_id, c.user_id, o.slug::text,
             COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text,
             (p.published_at IS NOT NULL)
      FROM public.referral_codes c
      JOIN public.organizations o ON o.id = c.organization_id
      JOIN public.organization_memberships m
        ON m.organization_id = c.organization_id AND m.user_id = c.user_id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      LEFT JOIN public.organization_public_profiles p ON p.organization_id = o.id
      WHERE c.code = invite_code
        AND c.revoked_at IS NULL
        AND o.status = 'active'
        AND m.status = 'active'
      LIMIT 1
    $$
    """)
  end

  # The notification type constraint is rebuilt by several milestones; read
  # its current list instead of restating it, so order never matters.
  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
