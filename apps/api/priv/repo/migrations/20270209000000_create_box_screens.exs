defmodule Palee.Repo.Migrations.CreateBoxScreens do
  @moduledoc """
  ADR-253: the box screen («Οθόνη box»), a TV on the wall that shows the
  day's classes, WODs, leaderboards and the class timer.

    * `box_screens` – one row per screen: its name, its branch (null for the
      whole box), the pending pairing code (only its SHA-256, valid for 15
      minutes), the version its display token must carry, and the screen's
      staff override («καρφίτσωμα»), with who changed it last;
    * `palee_box_screen_pairing(hash, now)` – the one lookup a TV makes
      before it belongs to any box: an unexpired code's hash to its box and
      screen. Pins only `search_path`; the claim itself runs in the box's
      tenant scope with the row locked.
  """

  use Ecto.Migration

  def up do
    create table(:box_screens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :location_id,
          references(:facility_locations, type: :binary_id, on_delete: :delete_all)

      add :name, :string, size: 60, null: false
      add :pairing_code_hash, :binary
      add :pairing_code_expires_at, :utc_datetime_usec
      add :token_version, :integer, null: false, default: 0
      add :paired_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec
      add :override_view, :string, size: 20
      add :override_slot_id, :binary_id
      add :override_until, :utc_datetime_usec
      add :focus_changed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :focus_changed_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:box_screens, [:organization_id])

    create unique_index(:box_screens, [:pairing_code_hash],
             where: "pairing_code_hash IS NOT NULL",
             name: :box_screens_pairing_code_hash_index
           )

    create constraint(:box_screens, :box_screens_check,
             check: """
             char_length(btrim(name)) BETWEEN 1 AND 60
             AND token_version >= 0
             AND (pairing_code_hash IS NULL) = (pairing_code_expires_at IS NULL)
             AND (pairing_code_hash IS NULL OR octet_length(pairing_code_hash) = 32)
             AND (override_view IS NULL
                  OR override_view IN ('wod', 'timer', 'leaderboard', 'bookings', 'class'))
             AND (override_view IS NOT NULL OR (override_slot_id IS NULL AND override_until IS NULL))
             AND (override_view IS DISTINCT FROM 'class' OR override_slot_id IS NOT NULL)
             """
           )

    execute("""
    CREATE TRIGGER box_screens_apply_tenant_context
    BEFORE INSERT OR UPDATE ON box_screens
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY box_screens_tenant_policy ON box_screens
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE box_screens ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE box_screens FORCE ROW LEVEL SECURITY")

    # The TV types its code before it belongs to any box: this answers only
    # which box and screen an unexpired code's hash names, nothing else.
    execute("""
    CREATE OR REPLACE FUNCTION palee_box_screen_pairing(code_hash bytea, at timestamptz)
    RETURNS TABLE (organization_id uuid, screen_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT s.organization_id, s.id
      FROM public.box_screens s
      JOIN public.organizations o ON o.id = s.organization_id
      WHERE s.pairing_code_hash = code_hash
        AND s.pairing_code_expires_at > at
        AND o.status = 'active'
      LIMIT 1
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_box_screen_pairing(bytea, timestamptz)")
    drop table(:box_screens)
  end
end
