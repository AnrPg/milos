defmodule Palee.Repo.Migrations.AddPublicThemeSlugFunction do
  use Ecto.Migration

  # TD-092 / ADR-131: the public `GET /api/theme` (unauthenticated - it paints
  # the login page and the app shell) read the theme from gamification
  # settings with no session scope. Settings are tenant rows, so under the
  # production runtime role the read was always empty and every gym got the
  # default theme, whatever its admin chose.
  #
  # The theme is cosmetic and public by design, so this narrow SECURITY
  # DEFINER function answers exactly one value - the theme slug of an active
  # organization identified by its (public) slug - and nothing else.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_public_theme_slug(org_slug text)
    RETURNS text
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT gs.theme_slug::text
      FROM public.gamification_settings gs
      JOIN public.organizations o ON o.id = gs.organization_id
      WHERE o.slug = org_slug
        AND o.status = 'active'
      ORDER BY gs.updated_at DESC
      LIMIT 1
    $$
    """)

    # EXECUTE stays with PUBLIC (the default), like the other palee_*
    # SECURITY DEFINER helpers.
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_public_theme_slug(text)")
  end
end
