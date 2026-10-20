defmodule MilosTraining.Repo.Migrations.CheckInAndWallet do
  use Ecto.Migration

  # ADR-155 (P2-M7): QR check-in and Wallet.
  #
  # - facility_locations.door_secret: a random per-location seed. Door codes
  #   are HMAC(key, location ‖ 30-s window) where the key is derived from this
  #   seed AND the application secret, so a database dump alone cannot forge
  #   a door code. «Νέος κωδικός πόρτας» replaces the seed.
  # - Every check-in records how it happened (`method`): door_qr, member_qr,
  #   wallet, desk_search or self. Staff roster marks leave it empty.
  # - facility_check_in_settings: the owner's «Ρυθμίσεις › Check-in».
  # - facility_visitor_scans: a person who is not a member scanned the door;
  #   the desk lists them as «Επισκέπτης».
  # - wallet_passes: a member's Apple/Google Wallet card per box. The barcode
  #   is signed with the serial, so revoking the row stops the card at once.
  #   wallet_device_registrations: Apple devices that asked for updates of a
  #   pass (PassKit web service); a child of wallet_passes.
  # - Two lookups run before any tenant is known and are narrow SECURITY
  #   DEFINER functions: which box a door belongs to (name and branding only,
  #   what the door itself shows), and which box a Wallet serial belongs to.

  @methods ~w(door_qr member_qr wallet desk_search self)

  def up do
    alter table(:facility_locations) do
      add :door_secret, :binary,
        null: false,
        default:
          fragment(
            "decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex')"
          )

      add :door_secret_rotated_at, :utc_datetime_usec
    end

    alter table(:facility_check_ins) do
      add :method, :string, null: false, default: "self"
    end

    execute("UPDATE facility_check_ins SET method = 'desk_search' WHERE source = 'staff'")

    create constraint(:facility_check_ins, :facility_check_ins_method_check,
             check: "method IN (#{in_list(@methods)})"
           )

    alter table(:class_attendance_records) do
      add :check_in_method, :string
    end

    execute(
      "UPDATE class_attendance_records SET check_in_method = 'self' WHERE params->>'source' = 'self'"
    )

    create constraint(:class_attendance_records, :class_attendance_records_method_check,
             check: "check_in_method IS NULL OR check_in_method IN (#{in_list(@methods)})"
           )

    create table(:facility_check_in_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :window_before_minutes, :integer, null: false, default: 30
      add :window_after_minutes, :integer, null: false, default: 15
      add :open_gym_requires_package, :boolean, null: false, default: true
      add :visitor_trial_offer, :boolean, null: false, default: true
      add :desk_override, :boolean, null: false, default: false
      add :door_rotation_seconds, :integer, null: false, default: 30

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:facility_check_in_settings, [:organization_id])

    create constraint(:facility_check_in_settings, :facility_check_in_settings_limits_check,
             check: """
             window_before_minutes BETWEEN 0 AND 120
             AND window_after_minutes BETWEEN 0 AND 120
             AND door_rotation_seconds IN (15, 30, 60)
             """
           )

    create table(:facility_visitor_scans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :location_id,
          references(:facility_locations, type: :binary_id, on_delete: :nilify_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :scanned_at, :utc_datetime_usec, null: false
      add :trial_offered, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:facility_visitor_scans, [:organization_id, :scanned_at])
    create index(:facility_visitor_scans, [:user_id])

    create table(:wallet_passes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :serial, :string, null: false
      # SHA-256 of the PassKit authenticationToken; the token itself only
      # lives inside the pass on the member's phone.
      add :auth_token_hash, :binary, null: false
      add :revoked_at, :utc_datetime_usec
      add :last_updated_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wallet_passes, [:serial])
    create index(:wallet_passes, [:user_id])
    create index(:wallet_passes, [:organization_id, :user_id])

    create unique_index(:wallet_passes, [:organization_id, :user_id, :platform],
             where: "revoked_at IS NULL",
             name: :wallet_passes_one_active_index
           )

    create constraint(:wallet_passes, :wallet_passes_platform_check,
             check: "platform IN ('apple', 'google')"
           )

    create table(:wallet_device_registrations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pass_id, references(:wallet_passes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :device_library_id, :string, null: false
      add :push_token, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wallet_device_registrations, [:device_library_id, :pass_id])
    create index(:wallet_device_registrations, [:pass_id])

    org = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    me = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    for table <- ~w(facility_check_in_settings facility_visitor_scans wallet_passes) do
      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      FOR ALL USING (#{org}) WITH CHECK (#{org})
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Εγώ › Συνδεδεμένες συσκευές lists a person's cards at every box.
    execute("""
    CREATE POLICY wallet_passes_owner_read_policy ON wallet_passes
    FOR SELECT USING (#{me})
    """)

    lookups()
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_wallet_device_serials(text, timestamp)")
    execute("DROP FUNCTION IF EXISTS milos_wallet_pass_organization(text)")
    execute("DROP FUNCTION IF EXISTS milos_door_location(uuid)")
    drop table(:wallet_device_registrations)
    drop table(:wallet_passes)
    drop table(:facility_visitor_scans)
    drop table(:facility_check_in_settings)
    drop constraint(:class_attendance_records, :class_attendance_records_method_check)

    alter table(:class_attendance_records) do
      remove :check_in_method
    end

    drop constraint(:facility_check_ins, :facility_check_ins_method_check)

    alter table(:facility_check_ins) do
      remove :method
    end

    alter table(:facility_locations) do
      remove :door_secret_rotated_at
      remove :door_secret
    end
  end

  defp lookups do
    # The box behind a door: what the door already shows (name, logo,
    # colour, the location's name), for an active box and a location that
    # is not archived. Never the seed.
    execute("""
    CREATE OR REPLACE FUNCTION milos_door_location(door_location_id uuid)
    RETURNS TABLE (organization_id uuid, slug text, name text, logo_url text,
                   primary_color text, location_name text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text, l.name::text
      FROM public.facility_locations l
      JOIN public.organizations o ON o.id = l.organization_id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE l.id = door_location_id
        AND l.archived_at IS NULL
        AND o.status = 'active'
      LIMIT 1
    $$
    """)

    # PassKit calls carry a serial and the pass's own token, never a tenant.
    execute("""
    CREATE OR REPLACE FUNCTION milos_wallet_pass_organization(pass_serial text)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT p.organization_id FROM public.wallet_passes p WHERE p.serial = pass_serial LIMIT 1
    $$
    """)

    # «Which of my passes changed?», asked by an Apple device by its id.
    execute("""
    CREATE OR REPLACE FUNCTION milos_wallet_device_serials(device text, since timestamp)
    RETURNS TABLE (serial text, last_updated_at timestamp)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT p.serial::text, p.last_updated_at
      FROM public.wallet_device_registrations r
      JOIN public.wallet_passes p ON p.id = r.pass_id
      WHERE r.device_library_id = device
        AND (since IS NULL OR p.last_updated_at > since)
    $$
    """)
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
