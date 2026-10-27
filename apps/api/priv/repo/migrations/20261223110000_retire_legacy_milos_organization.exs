defmodule Palee.Repo.Migrations.RetireLegacyMilosOrganization do
  use Ecto.Migration

  # TD-109 item 8: the 2026-08 tenancy migrations seed a "Milos Training"
  # organization (slug legacy-milos-training) that older RLS policies fall back
  # to through palee_legacy_organization_id(). A new database (production's
  # palee-db) would otherwise always contain it. Here:
  #   * with no members it is deleted (with its seeded settings);
  #   * with members (a long-lived dev database) it is renamed to a neutral
  #     legacy organization, so no data is lost;
  #   * the fallback function looks up the neutral slug, which
  #     `Palee.Organizations.ensure_legacy_organization_for_migration/0` uses.
  # Without such an organization the fallback is NULL and unscoped sessions
  # simply match nothing.
  #
  # Row level security (FORCE'd, so it binds this owner role too) is switched
  # off for the change and back on in the same transaction; the ALTER holds an
  # exclusive lock, so no other session sees the gap.

  @tables ~w(organizations organization_settings organization_memberships)

  def up do
    with_rls_off(fn ->
      repo().query!("""
      DO $$
      DECLARE
        legacy_id uuid;
      BEGIN
        SELECT id INTO legacy_id FROM public.organizations WHERE slug = 'legacy-milos-training';

        IF legacy_id IS NULL THEN
          RETURN;
        END IF;

        IF EXISTS (SELECT 1 FROM public.organization_memberships WHERE organization_id = legacy_id) THEN
          UPDATE public.organizations
          SET slug = 'legacy-organization', name = 'Legacy organization'
          WHERE id = legacy_id;

          UPDATE public.organization_settings
          SET brand_name = 'Legacy organization'
          WHERE organization_id = legacy_id AND brand_name IN ('Milos Training', 'Legacy Milos Training');
        ELSE
          DELETE FROM public.organization_settings WHERE organization_id = legacy_id;
          DELETE FROM public.organizations WHERE id = legacy_id;
        END IF;
      END
      $$
      """)
    end)

    repo().query!(legacy_function("legacy-organization"))
  end

  def down do
    execute(legacy_function("legacy-milos-training"))
  end

  defp legacy_function(slug) do
    """
    CREATE OR REPLACE FUNCTION palee_legacy_organization_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    AS $$
      SELECT id FROM public.organizations WHERE slug = '#{slug}' LIMIT 1
    $$
    """
  end

  # Only tables that have RLS on are switched, and switched back.
  defp with_rls_off(fun) do
    %{rows: rows} =
      repo().query!(
        "SELECT relname FROM pg_class WHERE relname = ANY($1) AND relkind = 'r' AND relrowsecurity",
        [@tables]
      )

    tables = List.flatten(rows)
    Enum.each(tables, &repo().query!("ALTER TABLE #{&1} DISABLE ROW LEVEL SECURITY"))
    fun.()
    Enum.each(tables, &repo().query!("ALTER TABLE #{&1} ENABLE ROW LEVEL SECURITY"))
  end
end
