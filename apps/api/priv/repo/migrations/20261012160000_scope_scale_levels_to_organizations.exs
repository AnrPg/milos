defmodule Palee.Repo.Migrations.ScopeScaleLevelsToOrganizations do
  use Ecto.Migration

  # ADR-128 / TD-063: scale levels become tenant-owned.
  #
  # `scale_levels` was a single global table, so `PUT /admin/scale-levels` in
  # any gym rewrote every gym's scaling vocabulary. This migration expands,
  # backfills and enforces in one transaction:
  #
  # 1. expand   - nullable `organization_id` (FK organizations, ON DELETE
  #               CASCADE like every sibling tenant table) and drop the global
  #               slug / sort_order unique indexes (owner-approved for TD-063).
  # 2. backfill - copy every global row into every existing organization with a
  #               fresh id, repoint `exercise_variations.scale_level_id` to the
  #               copy in the variation's own organization (matched by slug,
  #               which was globally unique), then delete the global originals.
  #               Executions and training-log entries store the *slug*, not the
  #               id, so they need no remap: each org's copy keeps the slug.
  # 3. enforce  - NOT NULL, per-organization unique indexes, a composite FK so a
  #               variation can only reference a level of its own organization,
  #               the tenant-context insert trigger, and forced RLS with the
  #               sibling `organization_id = app.organization_id` policy.
  #
  # Like the earlier tenant backfills, this runs as the migration (owner /
  # superuser) role, which is not subject to the RLS policies it reads through.
  #
  # `down` collapses the per-organization sets back into one global set. It is
  # lossy once organizations have diverged: the oldest organization (that has
  # any levels) supplies the global set, slugs only other organizations used are kept as
  # inactive rows (so variations still resolve), and per-organization labels
  # and ordering for shared slugs are lost.

  @tenant_predicate "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"

  def up do
    alter table(:scale_levels) do
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    drop_if_exists index(:scale_levels, [:slug], name: :scale_levels_slug_index)
    drop_if_exists index(:scale_levels, [:sort_order], name: :scale_levels_sort_order_index)

    execute("""
    INSERT INTO scale_levels
      (id, organization_id, slug, label, sort_order, is_active, inserted_at, updated_at)
    SELECT gen_random_uuid(), organizations.id, global.slug, global.label,
           global.sort_order, global.is_active, global.inserted_at, global.updated_at
    FROM scale_levels AS global
    CROSS JOIN organizations
    WHERE global.organization_id IS NULL
    """)

    execute("""
    UPDATE exercise_variations AS variation
    SET scale_level_id = copy.id
    FROM scale_levels AS global, scale_levels AS copy
    WHERE variation.scale_level_id = global.id
      AND global.organization_id IS NULL
      AND copy.organization_id = variation.organization_id
      AND copy.slug = global.slug
    """)

    # Any variation still pointing at a global row would make this fail on the
    # existing FK, aborting the whole migration rather than orphaning data.
    execute("DELETE FROM scale_levels WHERE organization_id IS NULL")

    execute("ALTER TABLE scale_levels ALTER COLUMN organization_id SET NOT NULL")

    create unique_index(:scale_levels, [:organization_id, :slug],
             name: :scale_levels_organization_id_slug_index
           )

    create unique_index(:scale_levels, [:organization_id, :sort_order],
             name: :scale_levels_organization_id_sort_order_index,
             where: "is_active = true"
           )

    create unique_index(:scale_levels, [:organization_id, :id],
             name: :scale_levels_organization_id_id_index
           )

    # Same constraint name so `foreign_key_constraint(:scale_level_id)` keeps
    # mapping violations. NO ACTION (checked at statement end) instead of
    # RESTRICT so an organization delete can cascade through both tables;
    # application deletes of a referenced level are still rejected.
    execute("""
    ALTER TABLE exercise_variations
      DROP CONSTRAINT exercise_variations_scale_level_id_fkey,
      ADD CONSTRAINT exercise_variations_scale_level_id_fkey
        FOREIGN KEY (organization_id, scale_level_id)
        REFERENCES scale_levels (organization_id, id)
    """)

    execute("""
    CREATE TRIGGER scale_levels_apply_tenant_context
    BEFORE INSERT OR UPDATE ON scale_levels
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY scale_levels_tenant_policy ON scale_levels
    USING (#{@tenant_predicate})
    WITH CHECK (#{@tenant_predicate})
    """)

    execute("ALTER TABLE scale_levels ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE scale_levels FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("ALTER TABLE scale_levels NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE scale_levels DISABLE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS scale_levels_tenant_policy ON scale_levels")
    execute("DROP TRIGGER IF EXISTS scale_levels_apply_tenant_context ON scale_levels")

    execute("""
    ALTER TABLE exercise_variations
      DROP CONSTRAINT exercise_variations_scale_level_id_fkey
    """)

    drop index(:scale_levels, [:organization_id, :id],
           name: :scale_levels_organization_id_id_index
         )

    drop index(:scale_levels, [:organization_id, :sort_order],
           name: :scale_levels_organization_id_sort_order_index
         )

    drop index(:scale_levels, [:organization_id, :slug],
           name: :scale_levels_organization_id_slug_index
         )

    execute("ALTER TABLE scale_levels ALTER COLUMN organization_id DROP NOT NULL")

    # Global set = the oldest organization's levels, then every other slug once
    # (inactive, ordered after the canonical set) so variations still resolve.
    execute("""
    WITH canonical AS (
      SELECT organizations.id
      FROM organizations
      WHERE EXISTS (
        SELECT 1 FROM scale_levels WHERE scale_levels.organization_id = organizations.id
      )
      ORDER BY organizations.inserted_at, organizations.id
      LIMIT 1
    ),
    ranked AS (
      SELECT level.*,
             (level.organization_id = (SELECT id FROM canonical)) AS is_canonical,
             row_number() OVER (
               PARTITION BY level.slug
               ORDER BY (level.organization_id = (SELECT id FROM canonical)) DESC,
                        organizations.inserted_at, level.organization_id
             ) AS slug_rank
      FROM scale_levels AS level
      JOIN organizations ON organizations.id = level.organization_id
    ),
    picked AS (
      SELECT ranked.*,
             row_number() OVER (ORDER BY ranked.slug) AS extra_rank
      FROM ranked
      WHERE slug_rank = 1
    )
    INSERT INTO scale_levels
      (id, organization_id, slug, label, sort_order, is_active, inserted_at, updated_at)
    SELECT gen_random_uuid(), NULL, slug, label,
           CASE WHEN is_canonical THEN sort_order ELSE 1000 + extra_rank END,
           is_canonical AND is_active,
           inserted_at, updated_at
    FROM picked
    """)

    execute("""
    UPDATE exercise_variations AS variation
    SET scale_level_id = global.id
    FROM scale_levels AS tenant_level, scale_levels AS global
    WHERE variation.scale_level_id = tenant_level.id
      AND tenant_level.organization_id IS NOT NULL
      AND global.organization_id IS NULL
      AND global.slug = tenant_level.slug
    """)

    execute("DELETE FROM scale_levels WHERE organization_id IS NOT NULL")

    alter table(:scale_levels) do
      remove :organization_id
    end

    create unique_index(:scale_levels, [:slug])
    create unique_index(:scale_levels, [:sort_order], where: "is_active = true")

    execute("""
    ALTER TABLE exercise_variations
      ADD CONSTRAINT exercise_variations_scale_level_id_fkey
        FOREIGN KEY (scale_level_id) REFERENCES scale_levels (id) ON DELETE RESTRICT
    """)
  end
end
