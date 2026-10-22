defmodule Palee.Repo.Migrations.RenameOldPrefixBeforePendingMigrations do
  use Ecto.Migration

  # Databases migrated before the Palee rename hold their helper functions
  # under the old `milos_*` prefix, but every migration from here on calls
  # them as `palee_*`. 20261126100000 renames them, yet it sorts after the
  # migrations that already need the new names, so such a database stopped at
  # 20261018101000 ("function palee_apply_tenant_context() does not exist").
  #
  # This runs the same idempotent rename before any of those migrations. It is
  # a no-op on a fresh database. Queued Oban jobs keep their old worker names
  # until 20261126100000, so the old release can still run them meanwhile.
  # Rolling back is left to 20261126100000's own down.

  def up do
    execute("""
    DO $rename$
    DECLARE
      fn record;
    BEGIN
      FOR fn IN
        SELECT p.oid::regprocedure AS signature, p.proname
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname LIKE 'milos\\_%'
          AND NOT EXISTS (
            SELECT 1 FROM pg_depend d
            WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
          )
      LOOP
        EXECUTE format('ALTER FUNCTION %s RENAME TO %I', fn.signature, 'palee' || substr(fn.proname, 6));
      END LOOP;

      FOR fn IN
        SELECT p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.prosrc LIKE '%milos\\_%'
          AND NOT EXISTS (
            SELECT 1 FROM pg_depend d
            WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
          )
      LOOP
        EXECUTE replace(pg_get_functiondef(fn.oid), 'milos_', 'palee_');
      END LOOP;
    END
    $rename$;
    """)
  end

  def down, do: :ok
end
