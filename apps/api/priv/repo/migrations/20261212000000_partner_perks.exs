defmodule Palee.Repo.Migrations.PartnerPerks do
  @moduledoc """
  ADR-191: partner perks. A gym or an independent coach publishes deals its
  clients use at partner businesses («10% στο SupplementsX με τον κωδικό
  COACHNIKOS», a personal QR shown at the counter). The model is an open
  policy, not a fixed form:

  - `perks`: the partner, the redemption method (a strategy, ADR-191 §2),
    the branches it is valid at (ADR-186 §8 covering item), the lifecycle
    and the counters. `valid_from` / `valid_until` mirror the current
    version's window so lists filter without reading JSON.
    `claims_count` / `uses_count` move in the same transaction as a claim
    or a use, under a lock on the perk row, so caps hold under concurrency.
  - `perk_versions`: what members agree to when they claim: the benefit,
    the rules (windows, recurring windows, limits, eligibility, channel,
    stacking notes), the method's settings and the terms, each a
    validated structured document carrying its own `schema_version`. A
    change after the first claim is a new version; claims keep theirs.
  - `perk_codes`: the pool of single-use codes a partner handed over.
  - `perk_claims`: a member claimed a perk (its code, link or QR is
    revealed) under one version; a use is stamped once. `token_hash` is
    the SHA-256 of a personal QR's secret nonce, which the partner's signed
    link carries.

  Every table is tenant scoped: RLS forced, the tenant trigger, composite
  foreign keys that keep versions, codes and claims inside the perk's
  organization.
  """

  use Ecto.Migration

  @org "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
  @methods ~w(shared_code code_pool personal_qr partner_link show_membership)

  def up do
    perks()
    perk_versions()
    perk_codes()
    perk_claims()

    for table <- ~w(perks perk_versions perk_codes perk_claims) do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      FOR ALL USING (#{@org}) WITH CHECK (#{@org})
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    drop table(:perk_claims)
    drop table(:perk_codes)
    drop table(:perk_versions)
    drop table(:perks)
  end

  defp perks do
    create table(:perks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :partner_name, :text, null: false
      add :partner_url, :text
      add :partner_address, :text
      # A ready `box_photo` of the business (ADR-148); plain id, released
      # through the media lifecycle like club covers.
      add :logo_media_id, :binary_id
      add :redemption_method, :string, null: false
      add :current_version, :integer, null: false, default: 1
      add :valid_from, :date
      add :valid_until, :date
      add :all_locations, :boolean, null: false, default: true
      add :location_ids, {:array, :binary_id}, null: false, default: []
      add :status, :string, null: false, default: "draft"
      add :claims_count, :integer, null: false, default: 0
      add :uses_count, :integer, null: false, default: 0
      add :published_at, :utc_datetime_usec
      add :paused_at, :utc_datetime_usec
      add :expired_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:perks, [:id, :organization_id], name: :perks_id_organization_index)
    create index(:perks, [:organization_id, :status])

    checks = [
      redemption_method: "redemption_method IN (#{in_list(@methods)})",
      status: "status IN ('draft', 'published', 'paused', 'expired')",
      window: "valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from",
      counts: "claims_count >= 0 AND uses_count >= 0 AND uses_count <= claims_count",
      version: "current_version >= 1",
      location_scope: "all_locations OR cardinality(location_ids) > 0"
    ]

    for {name, check} <- checks do
      create constraint(:perks, :"perks_#{name}_check", check: check)
    end
  end

  defp perk_versions do
    create table(:perk_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :perk_id, :binary_id, null: false
      add :version, :integer, null: false
      # Validated documents (embedded schemas), each with `schema_version`.
      add :benefit, :map, null: false
      add :rules, :map, null: false
      add :redemption, :map, null: false
      add :terms, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE perk_versions ADD CONSTRAINT perk_versions_perk_id_fkey
    FOREIGN KEY (perk_id, organization_id) REFERENCES perks (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:perk_versions, [:perk_id, :version])
    create index(:perk_versions, [:organization_id])

    create constraint(:perk_versions, :perk_versions_documents_check,
             check:
               "version >= 1 AND jsonb_typeof(benefit) = 'object' AND jsonb_typeof(rules) = 'object' " <>
                 "AND jsonb_typeof(redemption) = 'object' AND benefit ? 'schema_version' " <>
                 "AND rules ? 'schema_version' AND redemption ? 'schema_version'"
           )
  end

  defp perk_codes do
    create table(:perk_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :perk_id, :binary_id, null: false
      add :code, :text, null: false
      add :claim_id, :binary_id
      add :assigned_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE perk_codes ADD CONSTRAINT perk_codes_perk_id_fkey
    FOREIGN KEY (perk_id, organization_id) REFERENCES perks (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:perk_codes, [:perk_id, :code])

    create index(:perk_codes, [:perk_id, :inserted_at],
             where: "claim_id IS NULL",
             name: :perk_codes_free_index
           )

    create unique_index(:perk_codes, [:claim_id], where: "claim_id IS NOT NULL")
    create index(:perk_codes, [:organization_id])

    create constraint(:perk_codes, :perk_codes_assignment_check,
             check: "(claim_id IS NULL) = (assigned_at IS NULL) AND btrim(code) <> ''"
           )
  end

  defp perk_claims do
    create table(:perk_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :perk_id, :binary_id, null: false
      # The version the member agreed to.
      add :perk_version, :integer, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # What the member shows: the shared code, their pool code, or the short
      # reference under their QR or membership card.
      add :code, :text, null: false
      add :token_hash, :text
      add :status, :string, null: false, default: "claimed"
      add :claimed_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :used_via, :string
      add :used_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE perk_claims ADD CONSTRAINT perk_claims_perk_id_fkey
    FOREIGN KEY (perk_id, organization_id) REFERENCES perks (id, organization_id) ON DELETE CASCADE
    """)

    create index(:perk_claims, [:organization_id, :perk_id, :claimed_at])
    create index(:perk_claims, [:perk_id, :user_id, :claimed_at])
    create index(:perk_claims, [:user_id])

    create constraint(:perk_claims, :perk_claims_status_check,
             check:
               "(status = 'claimed' AND used_at IS NULL AND revoked_at IS NULL) OR " <>
                 "(status = 'used' AND used_at IS NOT NULL AND used_via IS NOT NULL) OR " <>
                 "(status = 'revoked' AND revoked_at IS NOT NULL)"
           )

    create constraint(:perk_claims, :perk_claims_used_via_check,
             check: "used_via IS NULL OR used_via IN ('partner_link', 'staff')"
           )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
