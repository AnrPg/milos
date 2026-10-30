defmodule Palee.Repo.Migrations.PartnerVerification do
  @moduledoc """
  ADR-280 §1, the verification side of public Partners. Every row is
  personal (the account's, not a business's): row security reads the acting
  person (`app.user_id`), the Palee team (`palee_acting_user_is_vendor()`)
  and system sessions (no acting person).

  - `partner_verifications`: one per person, permanent. Written only by the
    definer function `palee_partner_verify_by_membership()`, by vendors
    (sponsor path approvals, suspensions, sponsor penalties) and by system
    sessions. `sponsor_penalty_until` is the 60-day pause a sponsor gets when
    someone they vouched for is suspended.
  - `partner_verification_requests`: the sponsor path, one open per person
    (`collecting | in_review | expired`). The person never decides their own
    request (guard trigger). A verified phone number belongs to one account:
    the phone trigger refuses a number another account verified and did not
    withdraw.
  - `partner_phone_codes`: SMS codes, hashed; kept a day for the send limits.
  - `partner_sponsorships`: who was asked to vouch, and the answer. The
    candidate asks and cancels; the sponsor answers (guard trigger).
  - `partner_sponsor_links`: single-use 10-minute links; a sponsor reads and
    uses one only through the definer functions, by its token digest.
  - Definer functions: `palee_partner_membership_source(uuid)`,
    `palee_partner_verify_by_membership()`,
    `palee_partner_verification_badges(uuid[])`,
    `palee_partner_sponsor_standing(uuid[], timestamptz)`,
    `palee_partner_sponsor_link(bytea)`,
    `palee_partner_redeem_sponsor_link(bytea, timestamptz)`.
    Each pins only `search_path`.
  - Notification types `partner_vouch_request`, `partner_vouched`,
    `partner_verification_decided`, `partner_sponsor_penalty`.
  """

  use Ecto.Migration

  @notification_types ~w(partner_vouch_request partner_vouched partner_verification_decided partner_sponsor_penalty)
  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @system_or_vendor "(#{@me} IS NULL OR palee_acting_user_is_vendor())"

  def up do
    verifications()
    requests()
    phone_codes()
    sponsorships()
    links()
    functions()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    for signature <- [
          "palee_partner_redeem_sponsor_link(bytea, timestamptz)",
          "palee_partner_sponsor_link(bytea)",
          "palee_partner_sponsor_standing(uuid[], timestamptz)",
          "palee_partner_verification_badges(uuid[])",
          "palee_partner_verify_by_membership()",
          "palee_partner_membership_source(uuid)",
          "palee_partner_membership_organization(uuid)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{signature}")
    end

    drop table(:partner_sponsor_links)
    drop table(:partner_sponsorships)
    execute("DROP FUNCTION IF EXISTS palee_partner_sponsorships_guard()")
    drop table(:partner_phone_codes)
    drop table(:partner_verification_requests)
    execute("DROP FUNCTION IF EXISTS palee_partner_requests_guard()")
    execute("DROP FUNCTION IF EXISTS palee_partner_phone_unique()")
    drop table(:partner_verifications)
  end

  # -- tables --------------------------------------------------------------------

  defp verifications do
    create table(:partner_verifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :method, :text, null: false
      add :status, :text, null: false, default: "verified"
      add :verified_at, :utc_datetime_usec, null: false

      add :source_organization_id,
          references(:organizations, type: :binary_id, on_delete: :nilify_all)

      add :suspended_at, :utc_datetime_usec
      add :suspended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :sponsor_penalty_until, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_verifications, [:user_id])

    create constraint(:partner_verifications, :partner_verifications_method_check,
             check: "method IN ('membership', 'sponsors')"
           )

    create constraint(:partner_verifications, :partner_verifications_status_check,
             check: "status IN ('verified', 'suspended')"
           )

    policies(:partner_verifications,
      read: "user_id = #{@me} OR #{@system_or_vendor}",
      write: @system_or_vendor
    )
  end

  defp requests do
    create table(:partner_verification_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "collecting"
      add :consent_at, :utc_datetime_usec
      add :phone_ciphertext, :binary
      add :phone_hash, :binary
      add :phone_verified_at, :utc_datetime_usec
      add :selfie_code, :text, null: false
      add :selfie_key, :text
      add :selfie_uploaded_at, :utc_datetime_usec
      add :submitted_at, :utc_datetime_usec
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decision_reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:partner_verification_requests, [:user_id, :inserted_at])
    create index(:partner_verification_requests, [:status, :submitted_at])
    create index(:partner_verification_requests, [:phone_hash], where: "phone_hash IS NOT NULL")

    create unique_index(:partner_verification_requests, [:user_id],
             where: "status IN ('collecting', 'in_review', 'expired')",
             name: :partner_verification_requests_one_open_index
           )

    create constraint(:partner_verification_requests, :partner_verification_requests_status_check,
             check:
               "status IN ('collecting', 'in_review', 'approved', 'rejected', 'expired', 'withdrawn')"
           )

    create constraint(:partner_verification_requests, :partner_verification_requests_code_check,
             check: "selfie_code ~ '^[0-9]{4}$'"
           )

    create constraint(:partner_verification_requests, :partner_verification_requests_reason_check,
             check: "decision_reason IS NULL OR char_length(decision_reason) <= 500"
           )

    own = "user_id = #{@me}"

    policies(:partner_verification_requests,
      read: "#{own} OR #{@system_or_vendor}",
      write: "#{own} OR #{@system_or_vendor}"
    )

    # The person moves their own request through collecting, review,
    # withdrawal; only the Palee team (or a system session) decides it.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_requests_guard()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF #{@system_or_vendor} THEN
        RETURN NEW;
      END IF;

      IF TG_OP = 'UPDATE' AND (NEW.user_id <> OLD.user_id OR NEW.selfie_code <> OLD.selfie_code) THEN
        RAISE EXCEPTION 'partner verification request owner and code are immutable'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      IF NEW.status IN ('approved', 'rejected')
         OR NEW.decided_by_id IS NOT NULL
         OR (TG_OP = 'UPDATE' AND (NEW.decided_at IS DISTINCT FROM OLD.decided_at
             OR NEW.decision_reason IS DISTINCT FROM OLD.decision_reason))
         OR (TG_OP = 'INSERT' AND (NEW.decided_at IS NOT NULL OR NEW.decision_reason IS NOT NULL)) THEN
        RAISE EXCEPTION 'partner verification is decided by the Palee team'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      IF TG_OP = 'UPDATE' AND OLD.status IN ('approved', 'rejected', 'withdrawn') THEN
        RAISE EXCEPTION 'a closed partner verification request does not change'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER partner_verification_requests_guard
    BEFORE INSERT OR UPDATE ON partner_verification_requests
    FOR EACH ROW EXECUTE FUNCTION palee_partner_requests_guard()
    """)

    # One account per phone number: a number another account verified (and
    # did not withdraw) is refused, under a lock on the number so two
    # accounts cannot both take it. Definer, so it sees the other rows.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_phone_unique()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF NEW.phone_hash IS NULL OR NEW.status = 'withdrawn' THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(hashtextextended(encode(NEW.phone_hash, 'hex'), 280));

      IF EXISTS (
        SELECT 1 FROM public.partner_verification_requests r
        WHERE r.phone_hash = NEW.phone_hash
          AND r.user_id <> NEW.user_id
          AND r.status <> 'withdrawn'
          AND r.phone_verified_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'partner phone number is taken'
          USING ERRCODE = 'unique_violation',
                CONSTRAINT = 'partner_verification_requests_phone_taken';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER partner_verification_requests_phone_unique
    BEFORE INSERT OR UPDATE OF phone_hash, phone_verified_at, status ON partner_verification_requests
    FOR EACH ROW EXECUTE FUNCTION palee_partner_phone_unique()
    """)
  end

  defp phone_codes do
    create table(:partner_phone_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :request_id,
          references(:partner_verification_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :attempts, :integer, null: false, default: 0
      add :sent_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:partner_phone_codes, [:request_id, :sent_at])
    create index(:partner_phone_codes, [:user_id, :sent_at])

    create constraint(:partner_phone_codes, :partner_phone_codes_attempts_check,
             check: "attempts BETWEEN 0 AND 5"
           )

    own = "user_id = #{@me}"

    policies(:partner_phone_codes,
      read: "#{own} OR #{@system_or_vendor}",
      write: "#{own} OR #{@system_or_vendor}"
    )
  end

  defp sponsorships do
    create table(:partner_sponsorships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :candidate_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sponsor_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :text, null: false
      add :status, :text, null: false, default: "requested"
      add :requested_at, :utc_datetime_usec, null: false
      add :decided_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_sponsorships, [:candidate_id, :sponsor_id])
    create index(:partner_sponsorships, [:sponsor_id, :status, :decided_at])

    create constraint(:partner_sponsorships, :partner_sponsorships_pair_check,
             check: "candidate_id <> sponsor_id"
           )

    create constraint(:partner_sponsorships, :partner_sponsorships_channel_check,
             check: "channel IN ('buddy', 'link')"
           )

    create constraint(:partner_sponsorships, :partner_sponsorships_status_check,
             check: "status IN ('requested', 'vouched', 'declined', 'cancelled')"
           )

    party = "(candidate_id = #{@me} OR sponsor_id = #{@me})"

    for {name, command, clause} <- [
          {"read", "SELECT", "USING (#{party} OR #{@system_or_vendor})"},
          # The candidate asks a Buddy; a sponsor who opened the candidate's
          # link vouches at once.
          {"insert", "INSERT",
           "WITH CHECK (#{@system_or_vendor} OR " <>
             "(candidate_id = #{@me} AND channel = 'buddy' AND status = 'requested') OR " <>
             "(sponsor_id = #{@me} AND channel = 'link' AND status = 'vouched'))"},
          {"update", "UPDATE",
           "USING (#{party} OR #{@system_or_vendor}) WITH CHECK (#{party} OR #{@system_or_vendor})"},
          {"delete", "DELETE", "USING (candidate_id = #{@me} OR #{@system_or_vendor})"}
        ] do
      execute(
        "CREATE POLICY partner_sponsorships_#{name}_policy ON partner_sponsorships FOR #{command} #{clause}"
      )
    end

    # The pair never changes; the candidate only cancels or asks again, the
    # sponsor only answers (vouch | decline). Vendors and system sessions
    # are not limited.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_sponsorships_guard()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      me uuid := #{@me};
    BEGIN
      IF NEW.candidate_id <> OLD.candidate_id OR NEW.sponsor_id <> OLD.sponsor_id THEN
        RAISE EXCEPTION 'partner sponsorship pair is immutable';
      END IF;

      IF me IS NULL OR palee_acting_user_is_vendor() OR NEW.status = OLD.status THEN
        RETURN NEW;
      END IF;

      IF me = OLD.candidate_id
         AND ((OLD.status = 'requested' AND NEW.status = 'cancelled')
              OR (OLD.status = 'cancelled' AND NEW.status = 'requested')) THEN
        RETURN NEW;
      END IF;

      IF me = OLD.sponsor_id
         AND (NEW.status = 'vouched' OR (OLD.status = 'requested' AND NEW.status = 'declined')) THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'partner sponsorship change not allowed'
        USING ERRCODE = 'insufficient_privilege';
    END
    $$
    """)

    execute("""
    CREATE TRIGGER partner_sponsorships_guard
    BEFORE UPDATE ON partner_sponsorships
    FOR EACH ROW EXECUTE FUNCTION palee_partner_sponsorships_guard()
    """)

    secure(:partner_sponsorships)
  end

  defp links do
    create table(:partner_sponsor_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :candidate_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_sponsor_links, [:token_hash])
    create index(:partner_sponsor_links, [:candidate_id])

    own = "candidate_id = #{@me}"

    policies(:partner_sponsor_links,
      read: "#{own} OR #{@system_or_vendor}",
      write: "#{own} OR #{@system_or_vendor}"
    )
  end

  # -- functions -----------------------------------------------------------------

  defp functions do
    # The first live business (gym or independent coach, active, not demo)
    # where the person is an active subscribed member or holds a running
    # package. Internal: callable only by the definer functions below.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_membership_organization(person uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id
      FROM public.memberships m
      JOIN public.organizations o ON o.id = m.organization_id
      WHERE m.user_id = person
        AND o.status = 'active'
        AND o.activation = 'active'
        AND o.provider_kind IN ('gym', 'coach')
        AND m.user_type_snapshot <> 'guest'
        AND (m.leaving_on IS NULL OR m.leaving_on > CURRENT_DATE)
        AND (
          (m.status IN ('active', 'expiring', 'comped')
            AND (m.expires_on IS NULL OR m.expires_on >= CURRENT_DATE))
          OR EXISTS (
            SELECT 1 FROM public.membership_package_subscriptions s
            WHERE s.membership_id = m.id
              AND s.status = 'active'
              AND (s.starts_on IS NULL OR s.starts_on <= CURRENT_DATE)
              AND (s.ends_on IS NULL OR s.ends_on >= CURRENT_DATE)
          )
        )
      ORDER BY m.inserted_at, o.id
      LIMIT 1
    $$
    """)

    execute(
      "REVOKE EXECUTE ON FUNCTION palee_partner_membership_organization(uuid) FROM PUBLIC"
    )

    # ADR-280 §1: the membership that verifies a person. Answers only for
    # the session's own person, the Palee team and system sessions.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_membership_source(person uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT CASE
        WHEN #{@me} IS NULL OR person = #{@me} OR palee_acting_user_is_vendor()
          THEN palee_partner_membership_organization(person)
      END
    $$
    """)

    # The session's person is verified by a membership on first use.
    # Idempotent: an existing verification (of any method or status) is
    # returned as it is, so a suspension is never undone by a membership.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_verify_by_membership()
    RETURNS public.partner_verifications
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      me uuid := #{@me};
      source uuid;
      result public.partner_verifications;
    BEGIN
      IF me IS NULL THEN
        RETURN NULL;
      END IF;

      SELECT * INTO result FROM public.partner_verifications WHERE user_id = me;

      IF FOUND THEN
        RETURN result;
      END IF;

      source := palee_partner_membership_organization(me);

      IF source IS NULL THEN
        RETURN NULL;
      END IF;

      INSERT INTO public.partner_verifications
        (id, user_id, method, status, verified_at, source_organization_id, inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), me, 'membership', 'verified', now(), source, now(), now())
      ON CONFLICT (user_id) DO NOTHING;

      SELECT * INTO result FROM public.partner_verifications WHERE user_id = me;
      RETURN result;
    END
    $$
    """)

    # The deck's badges: for each verified (not suspended) person, how and
    # the name of the box of an active membership (nil if none). The deck
    # side applies the person's «Δείξε το box μου».
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_verification_badges(ids uuid[])
    RETURNS TABLE (user_id uuid, method text, box_name text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT v.user_id, v.method, o.name
      FROM public.partner_verifications v
      LEFT JOIN public.organizations o
        ON o.id = palee_partner_membership_organization(v.user_id)
      WHERE v.user_id = ANY(ids) AND v.status = 'verified'
    $$
    """)

    # Who among the session person's Buddies (ADR-193 mutual follows) may
    # vouch: method, status, penalty and vouches since `since`. Other people
    # are left out unless the session is the Palee team or the system.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_sponsor_standing(ids uuid[], since timestamptz)
    RETURNS TABLE (user_id uuid, method text, status text, penalty_until timestamptz, vouches bigint)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT v.user_id, v.method, v.status, v.sponsor_penalty_until,
        (SELECT count(*) FROM public.partner_sponsorships s
         WHERE s.sponsor_id = v.user_id AND s.status = 'vouched' AND s.decided_at >= since)
      FROM public.partner_verifications v
      WHERE v.user_id = ANY(ids)
        AND (
          #{@system_or_vendor}
          OR v.user_id = #{@me}
          OR (
            EXISTS (SELECT 1 FROM public.community_follows f
                    WHERE f.user_id = #{@me} AND f.target_type = 'user'
                      AND f.target_id = v.user_id AND f.status = 'active')
            AND EXISTS (SELECT 1 FROM public.community_follows b
                        WHERE b.user_id = v.user_id AND b.target_type = 'user'
                          AND b.target_id = #{@me} AND b.status = 'active')
          )
        )
    $$
    """)

    # A sponsor reads a candidate's link only by its token digest.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_sponsor_link(digest bytea)
    RETURNS TABLE (id uuid, candidate_id uuid, expires_at timestamptz, used_at timestamptz)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT l.id, l.candidate_id, l.expires_at, l.used_at
      FROM public.partner_sponsor_links l
      WHERE l.token_hash = digest AND #{@me} IS NOT NULL
    $$
    """)

    # Uses a live link once, as the session person: the candidate's id, or
    # nothing when the link is unknown, used, expired or one's own.
    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_redeem_sponsor_link(digest bytea, at timestamptz)
    RETURNS uuid
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      UPDATE public.partner_sponsor_links l
      SET used_by_id = #{@me}, used_at = at, updated_at = at
      WHERE l.token_hash = digest
        AND l.used_at IS NULL
        AND l.expires_at > at
        AND #{@me} IS NOT NULL
        AND l.candidate_id <> #{@me}
      RETURNING l.candidate_id
    $$
    """)
  end

  # -- helpers -------------------------------------------------------------------

  defp policies(table, read: read, write: write) do
    execute("CREATE POLICY #{table}_read_policy ON #{table} FOR SELECT USING (#{read})")

    execute(
      "CREATE POLICY #{table}_write_policy ON #{table} FOR ALL USING (#{write}) WITH CHECK (#{write})"
    )

    secure(table)
  end

  defp secure(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
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
