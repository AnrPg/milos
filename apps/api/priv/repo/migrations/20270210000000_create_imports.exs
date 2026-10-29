defmodule Palee.Repo.Migrations.CreateImports do
  @moduledoc """
  ADR-254: importing people and their history from a CSV file.

    * `imports` – one uploaded file: its encoding, delimiter, header, the
      mapping, the dry-run counts, the state of applying and undoing;
    * `import_rows` – every data row with its cells, its fingerprint, the
      planned outcome and, once applied, what it created. A fingerprint is
      applied once per business (`import_rows_applied_fingerprint_index`),
      which is what makes a retry or a re-upload create nothing twice;
    * `imported_people` – the people imports brought in or matched, with
      the email and phone (last 10 digits) later rows and files match on.

  People: `users.held_by_organization_id` marks a profile an import
  created and nobody has claimed yet («held»). Like a mock person (ADR-184)
  it is visible only to itself and the staff of that business:
  `palee_demo_user_visible` and every function that skips mock people with
  `u.demo_organization_id IS NULL` now skip held ones too, and
  `palee_notification_suppressed` keeps them from notifications. The mark
  is cleared when the person proves the inbox (email verification or a
  password reset). No foreign key on purpose, as for the demo marker.

  Visits: facility check-ins get the method `imported`.
  """

  use Ecto.Migration

  @tables ~w(imports import_rows imported_people)
  @staff_roles "ARRAY['owner', 'admin', 'coach', 'front_desk', 'accountant', 'janitor']::varchar[]"
  @check_in_methods ~w(door_qr door_poster door_nfc geofence member_qr wallet desk_search self)

  def up do
    create table(:imports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "draft"
      add :source, :string, null: false
      add :filename, :string, size: 255, null: false
      add :byte_size, :integer, null: false
      add :sha256, :string, size: 64, null: false
      add :encoding, :string, null: false
      add :delimiter, :string, size: 1, null: false
      add :header, {:array, :text}, null: false, default: []
      add :row_count, :integer, null: false
      add :mapping, {:array, :map}, null: false, default: []
      add :date_order, :string, null: false
      add :default_role, :string, null: false, default: "member"
      add :file_warnings, {:array, :string}, null: false, default: []
      add :preview, :map
      add :previewed_at, :utc_datetime_usec
      add :summary, :map
      add :applied_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :queued_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :undone_at, :utc_datetime_usec
      add :undone_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_error, :string, size: 500
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:imports, [:id, :organization_id], name: :imports_id_organization_index)
    create index(:imports, [:organization_id, :inserted_at])

    create constraint(:imports, :imports_check,
             check: """
             status IN ('draft', 'queued', 'applying', 'applied', 'failed', 'undone')
             AND source IN ('wodify', 'pushpress', 'zen_planner', 'arbox', 'excel')
             AND date_order IN ('dmy', 'mdy', 'ymd')
             AND default_role IN ('member', 'athlete')
             AND delimiter IN (',', ';', E'\\t')
             AND encoding IN ('utf8', 'utf16le', 'utf16be', 'windows1252', 'iso88597', 'windows1253')
             AND byte_size > 0 AND row_count >= 0
             """
           )

    create table(:import_rows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :import_id, :binary_id, null: false
      add :row_number, :integer, null: false
      add :cells, {:array, :text}, null: false, default: []
      add :fingerprint, :string, size: 64
      add :status, :string, null: false, default: "pending"
      add :outcome, :string
      add :warnings, {:array, :map}, null: false, default: []
      add :errors, {:array, :map}, null: false, default: []
      add :result, :map, null: false, default: fragment("'{}'::jsonb")
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :error_code, :string, size: 120
      add :applied_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE import_rows
    ADD CONSTRAINT import_rows_import_fkey
    FOREIGN KEY (import_id, organization_id)
    REFERENCES imports (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:import_rows, [:import_id, :row_number])
    create index(:import_rows, [:import_id, :status, :row_number])

    create unique_index(:import_rows, [:organization_id, :fingerprint],
             where: "status = 'applied'",
             name: :import_rows_applied_fingerprint_index
           )

    create constraint(:import_rows, :import_rows_check,
             check: """
             status IN ('pending', 'applied', 'skipped', 'failed', 'undone')
             AND (outcome IS NULL OR outcome IN
               ('create_person', 'update_person', 'already_imported', 'duplicate_row', 'invalid'))
             AND row_number > 0
             AND (status <> 'applied' OR fingerprint IS NOT NULL)
             """
           )

    create table(:imported_people, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :import_id, :binary_id, null: false
      add :created_profile, :boolean, null: false, default: false
      add :name, :string, size: 500
      add :email, :string, size: 320
      add :phone_key, :string, size: 10
      add :external_id, :string, size: 500
      add :credit_entry_id, :binary_id
      add :invited_at, :utc_datetime_usec
      add :invitation_id, :binary_id
      add :removed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:imported_people, [:organization_id, :user_id])
    create index(:imported_people, [:organization_id, :email], where: "email IS NOT NULL")

    create index(:imported_people, [:organization_id, :phone_key],
             where: "phone_key IS NOT NULL"
           )

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # ── Held profiles ───────────────────────────────────────────────────
    alter table(:users) do
      add :held_by_organization_id, :binary_id
    end

    create index(:users, [:held_by_organization_id], where: "held_by_organization_id IS NOT NULL")

    execute(demo_user_visible(held: true))
    execute(notification_suppressed(held: true))
    execute(rewrite_people_filters(:add))

    # ── Imported visits ─────────────────────────────────────────────────
    replace_method_check(@check_in_methods ++ ["imported"])
  end

  def down do
    execute("DELETE FROM facility_check_ins WHERE method = 'imported'")
    replace_method_check(@check_in_methods)

    execute(rewrite_people_filters(:remove))
    execute(notification_suppressed(held: false))
    execute(demo_user_visible(held: false))
    drop index(:users, [:held_by_organization_id])

    alter table(:users) do
      remove :held_by_organization_id
    end

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end

  defp replace_method_check(methods) do
    drop constraint(:facility_check_ins, :facility_check_ins_method_check)

    create constraint(:facility_check_ins, :facility_check_ins_method_check,
             check: "method IN (#{Enum.map_join(methods, ", ", &"'#{&1}'")})"
           )
  end

  # Mock (ADR-184) and held people alike: visible only to themselves and the
  # active staff of their business.
  defp demo_user_visible(held: held?) do
    {marker, business} =
      if held?,
        do:
          {"(u.demo_organization_id IS NOT NULL OR u.held_by_organization_id IS NOT NULL)",
           "COALESCE(u.demo_organization_id, u.held_by_organization_id)"},
        else: {"u.demo_organization_id IS NOT NULL", "u.demo_organization_id"}

    """
    CREATE OR REPLACE FUNCTION palee_demo_user_visible(p_user uuid, p_viewer uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT NOT EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = p_user AND #{marker}
          AND u.id IS DISTINCT FROM p_viewer
          AND NOT EXISTS (
            SELECT 1 FROM public.organization_memberships m
            WHERE m.organization_id = #{business}
              AND m.user_id = p_viewer AND m.status = 'active'
              AND m.roles && #{@staff_roles}))
    $$
    """
  end

  defp notification_suppressed(held: held?) do
    marker =
      if held?,
        do: "(u.demo_organization_id IS NOT NULL OR u.held_by_organization_id IS NOT NULL)",
        else: "u.demo_organization_id IS NOT NULL"

    """
    CREATE OR REPLACE FUNCTION palee_notification_suppressed(p_org uuid, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
               SELECT 1 FROM public.demo_records d
               WHERE d.source = 'users' AND d.record_id = p_user)
          OR EXISTS (
               SELECT 1 FROM public.users u
               WHERE u.id = p_user AND #{marker})
          OR EXISTS (
               SELECT 1 FROM public.organizations o
               WHERE o.id = p_org AND o.activation = 'demo'
                 AND NOT EXISTS (
                   SELECT 1 FROM public.organization_memberships m
                   WHERE m.organization_id = o.id AND m.user_id = p_user
                     AND m.status = 'active'
                     AND m.roles && #{@staff_roles}))
    $$
    """
  end

  # Every person-discovery function that skips mock people by
  # `u.demo_organization_id IS NULL` (people search, Around, buddies) skips
  # held people the same way. Rewritten from their current definitions, so
  # this stays right whichever migration defined them last.
  @mock_filter "u.demo_organization_id IS NULL"
  @both_filter "u.demo_organization_id IS NULL AND u.held_by_organization_id IS NULL"

  defp rewrite_people_filters(direction) do
    {from, to, guard} =
      case direction do
        :add -> {@mock_filter, @both_filter, "NOT LIKE"}
        :remove -> {@both_filter, @mock_filter, "LIKE"}
      end

    """
    DO $rewrite$
    DECLARE
      f record;
    BEGIN
      FOR f IN
        SELECT p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prosrc LIKE '%#{@mock_filter}%'
          AND p.prosrc #{guard} '%held_by_organization_id IS NULL%'
      LOOP
        EXECUTE replace(pg_get_functiondef(f.oid), '#{from}', '#{to}');
      END LOOP;
    END
    $rewrite$
    """
  end
end
