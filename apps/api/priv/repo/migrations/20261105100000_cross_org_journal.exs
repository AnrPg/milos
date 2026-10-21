defmodule Palee.Repo.Migrations.CrossOrgJournal do
  @moduledoc """
  ADR-162 (P2-M14): one journal across every provider.

  - `organizations.provider_kind` (`gym` | `coach`): an independent coach is
    a one-person organization (vision §7.10); Box ▾ shows the kind.
  - `organization_memberships.ended_at`, kept by a trigger whenever a
    membership leaves or regains `active`, so «πρώην» providers carry the day
    their access ended whichever code path changed the status.
  - `palee_my_providers()`: a definer lookup answering, for the caller only,
    every organization they are or were a member of (name, kind, brand,
    status, end date). A former provider's `organizations` row is invisible
    to the member's session, yet their journal still labels it.
  - `account_provider_selections`: the provider Box ▾ last picked.
  - «Οι coach μου» across providers (board 17, Q5): the default audience of
    the coach rungs is every active provider minus
    `journal_coach_audience_exclusions`; an entry can be narrowed to (or,
    for a provider-less entry, shared with) specific providers through
    `journal_entry_audiences`. The home provider of an entry always reads it
    on a coach rung, as before. `palee_journal_entry_shared_with_org` is the
    SQL twin of `Journal.Domain.CoachAudience`; a coach reads shared entries
    of other providers through additive coach-read policies, only while the
    member is an active member of the coach's organization.
  - Ροή text search: `pg_trgm` indexes on the text the journal holds.
  - `journal_exports`: the member's whole-journal export, built in the
    background and stored privately (board 17 extra).
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @acting_org "NULLIF(current_setting('app.organization_id', true), '')::uuid"
  @shareable ~w(execution training_log pr note check_in)
  @shared_tables [
    {"journal_notes", "note", "deleted_at IS NULL AND "},
    {"wellbeing_check_ins", "check_in", "deleted_at IS NULL AND "},
    {"user_pr_records", "pr", ""},
    {"workout_executions", "execution", ""},
    {"training_log_entries", "training_log", ""}
  ]
  @trigram_columns [
    {"journal_notes", "body"},
    {"journal_comments", "body"},
    {"training_log_entries", "title"},
    {"user_pr_records", "name"},
    {"wellbeing_check_in_answers", "note"},
    {"injury_reports", "description"},
    {"craving_entries", "note"}
  ]
  @notification_types ~w(journal_export_ready)

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    alter table(:organizations) do
      add :provider_kind, :string, null: false, default: "gym"
    end

    create constraint(:organizations, :organizations_provider_kind_check,
             check: "provider_kind IN ('gym', 'coach')"
           )

    alter table(:organization_memberships) do
      add :ended_at, :utc_datetime_usec
    end

    execute("""
    UPDATE organization_memberships SET ended_at = updated_at
    WHERE status IN ('suspended', 'revoked')
    """)

    execute("""
    CREATE FUNCTION palee_membership_track_end() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.status = 'active' THEN
        NEW.ended_at := NULL;
      ELSIF OLD.status = 'active' AND NEW.status IN ('suspended', 'revoked') THEN
        NEW.ended_at := now();
      END IF;
      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER organization_memberships_track_end
    BEFORE UPDATE OF status ON organization_memberships
    FOR EACH ROW EXECUTE FUNCTION palee_membership_track_end()
    """)

    execute("""
    CREATE FUNCTION palee_my_providers()
    RETURNS TABLE (
      organization_id uuid, name text, slug text, provider_kind text,
      logo_url text, primary_color text, membership_status text, roles text[],
      joined_at timestamp, ended_at timestamp, organization_status text
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.name::text, o.slug::text, o.provider_kind::text,
             s.brand_logo_url::text, s.brand_primary_color::text,
             m.status::text, m.roles::text[], m.joined_at, m.ended_at, o.status::text
      FROM public.organization_memberships m
      JOIN public.organizations o ON o.id = m.organization_id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE m.user_id = #{@acting_user}
        AND m.status IN ('active', 'suspended', 'revoked')
    $$
    """)

    create table(:account_provider_selections, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:journal_coach_audience_exclusions, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:journal_entry_audiences, primary_key: false) do
      add :entry_kind, :string, primary_key: true
      add :entry_id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:journal_entry_audiences, :journal_entry_audiences_kind_check,
             check: "entry_kind IN (#{in_list(@shareable)})"
           )

    create index(:journal_entry_audiences, [:user_id])

    create table(:journal_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :entry_count, :integer
      add :files, {:array, :map}, null: false, default: []
      add :error, :string
      add :requested_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:journal_exports, :journal_exports_status_check,
             check: "status IN ('pending', 'ready', 'failed')"
           )

    create index(:journal_exports, [:user_id, :requested_at])

    for table <- ~w(account_provider_selections journal_coach_audience_exclusions
                    journal_entry_audiences journal_exports) do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = #{@acting_user})
      WITH CHECK (user_id = #{@acting_user})
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # The member's audience rows are invisible to a coach's session, hence
    # SECURITY DEFINER; it answers one boolean about one entry and one gym.
    execute("""
    CREATE FUNCTION palee_journal_entry_shared_with_org(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, org uuid
    )
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT org IS NOT NULL
        AND org IS DISTINCT FROM entry_org_id
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = org AND m.user_id = entry_user_id AND m.status = 'active'
        )
        AND (
          EXISTS (
            SELECT 1 FROM public.journal_entry_audiences a
            WHERE a.entry_kind = kind AND a.entry_id = entry AND a.organization_id = org
              AND a.user_id = entry_user_id
          )
          OR (
            entry_org_id IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_entry_audiences a
              WHERE a.entry_kind = kind AND a.entry_id = entry AND a.user_id = entry_user_id
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_coach_audience_exclusions x
              WHERE x.user_id = entry_user_id AND x.organization_id = org
            )
          )
        )
    $$
    """)

    execute("""
    CREATE FUNCTION palee_entry_shared_with_acting_coach(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, visibility text
    )
    RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
      SELECT public.palee_journal_visibility_reaches_coach(visibility)
        AND #{@acting_org} IS NOT NULL
        AND public.palee_acting_user_coaches(#{@acting_org})
        AND public.palee_journal_entry_shared_with_org(
          kind, entry, entry_user_id, entry_org_id, #{@acting_org}
        )
    $$
    """)

    for {table, kind, guard} <- @shared_tables do
      execute("""
      CREATE POLICY #{table}_coach_shared_read_policy ON #{table}
      FOR SELECT
      USING (
        #{guard}palee_entry_shared_with_acting_coach(
          '#{kind}', id, user_id, organization_id, journal_visibility
        )
      )
      """)
    end

    for {table, column} <- @trigram_columns do
      execute("""
      CREATE INDEX #{table}_#{column}_trgm_index ON #{table}
      USING gin (#{column} gin_trgm_ops)
      """)
    end

    rewrite_check(
      "notifications",
      "notifications_type_check",
      "type",
      &Enum.uniq(&1 ++ @notification_types)
    )
  end

  def down do
    rewrite_check(
      "notifications",
      "notifications_type_check",
      "type",
      &(&1 -- @notification_types)
    )

    for {table, column} <- @trigram_columns do
      execute("DROP INDEX IF EXISTS #{table}_#{column}_trgm_index")
    end

    for {table, _kind, _guard} <- @shared_tables do
      execute("DROP POLICY IF EXISTS #{table}_coach_shared_read_policy ON #{table}")
    end

    execute(
      "DROP FUNCTION IF EXISTS palee_entry_shared_with_acting_coach(text, uuid, uuid, uuid, text)"
    )

    execute(
      "DROP FUNCTION IF EXISTS palee_journal_entry_shared_with_org(text, uuid, uuid, uuid, uuid)"
    )

    drop table(:journal_exports)
    drop table(:journal_entry_audiences)
    drop table(:journal_coach_audience_exclusions)
    drop table(:account_provider_selections)

    execute("DROP FUNCTION IF EXISTS palee_my_providers()")

    execute(
      "DROP TRIGGER IF EXISTS organization_memberships_track_end ON organization_memberships"
    )

    execute("DROP FUNCTION IF EXISTS palee_membership_track_end()")

    alter table(:organization_memberships) do
      remove :ended_at
    end

    drop constraint(:organizations, :organizations_provider_kind_check)

    alter table(:organizations) do
      remove :provider_kind
    end
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")

  # Several milestones rebuild this constraint; read the current list instead
  # of restating it, so their order never matters.
  defp rewrite_check(table, name, column, change) do
    values = current_values(name) |> change.()
    execute("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{column} IN (#{in_list(values)}))"
    )
  end

  defp current_values(name) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1", [
        name
      ])

    definition = definition |> String.split("::text[]") |> List.first()

    ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)
  end
end
