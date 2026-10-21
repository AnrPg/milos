defmodule Palee.Repo.Migrations.RenameDatabaseObjectsToPalee do
  use Ecto.Migration

  # The product was renamed to Palee. Earlier migrations now create every
  # helper function as `palee_*`, but databases migrated before the rename
  # still hold them under the old prefix. This migration brings those
  # databases in line, and is a no-op on a fresh database:
  #
  # 1. renames every function in `public` that still carries the old prefix,
  # 2. recreates every function whose body calls another one by its old name
  #    (plpgsql and string-bodied SQL functions resolve names at call time),
  # 3. points queued Oban jobs at the renamed worker modules.
  #
  # Policies, views, triggers and indexes reference functions by OID, so the
  # rename carries over to them without changes.
  @old_prefix "milos"
  @new_prefix "palee"
  @old_namespace "MilosTraining."
  @new_namespace "Palee."

  def up do
    rename_functions(@old_prefix, @new_prefix)
    rename_workers(@old_namespace, @new_namespace)
  end

  def down do
    rename_functions(@new_prefix, @old_prefix)
    rename_workers(@new_namespace, @old_namespace)
  end

  defp rename_functions(from, to) do
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
          AND p.proname LIKE '#{from}\\_%'
          AND NOT EXISTS (
            SELECT 1 FROM pg_depend d
            WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
          )
      LOOP
        EXECUTE format(
          'ALTER FUNCTION %s RENAME TO %I',
          fn.signature,
          '#{to}' || substr(fn.proname, #{String.length(from) + 1})
        );
      END LOOP;

      FOR fn IN
        SELECT p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.prosrc LIKE '%#{from}\\_%'
          AND NOT EXISTS (
            SELECT 1 FROM pg_depend d
            WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
          )
      LOOP
        EXECUTE replace(pg_get_functiondef(fn.oid), '#{from}_', '#{to}_');
      END LOOP;
    END
    $rename$;
    """)
  end

  defp rename_workers(from, to) do
    execute("""
    DO $oban$
    BEGIN
      IF to_regclass('public.oban_jobs') IS NOT NULL THEN
        UPDATE public.oban_jobs
        SET worker = '#{to}' || substr(worker, #{String.length(from) + 1})
        WHERE worker LIKE '#{from}%'
          AND state IN ('available', 'scheduled', 'retryable', 'executing');
      END IF;
    END
    $oban$;
    """)
  end
end
