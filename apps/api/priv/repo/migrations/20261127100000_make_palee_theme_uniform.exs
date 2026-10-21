defmodule Palee.Repo.Migrations.MakePaleeThemeUniform do
  use Ecto.Migration

  # Palee wears one brand palette for gyms and members alike: "frost" (light,
  # the default) and "graphite" (dark). Gyms no longer pick a theme, so the
  # per-gym theme column and its public lookup go away. A member's own choice
  # keeps its light or dark intent: the old dark themes become "graphite", the
  # old light ones the default (NULL).
  @gym_constraint :gamification_settings_theme_slug_check
  @user_constraint :users_preferred_theme_slug_check
  @legacy_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)
  @legacy_dark_slugs ~w(ember sage steel aurora royal volt noir)

  def up do
    execute(
      "UPDATE users SET preferred_theme_slug = 'graphite' WHERE preferred_theme_slug IN (#{quoted(@legacy_dark_slugs)})"
    )

    execute(
      "UPDATE users SET preferred_theme_slug = NULL WHERE preferred_theme_slug NOT IN ('frost', 'graphite')"
    )

    create constraint(:users, @user_constraint,
             check:
               "preferred_theme_slug IS NULL OR preferred_theme_slug IN ('frost', 'graphite')"
           )

    execute("DROP FUNCTION IF EXISTS palee_public_theme_slug(text)")

    alter table(:gamification_settings) do
      remove :theme_slug
    end
  end

  def down do
    alter table(:gamification_settings) do
      add :theme_slug, :string, null: false, default: "ember"
    end

    create constraint(:gamification_settings, @gym_constraint,
             check: "theme_slug IN (#{quoted(@legacy_slugs)})"
           )

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

    drop constraint(:users, @user_constraint)

    execute(
      "UPDATE users SET preferred_theme_slug = 'noir' WHERE preferred_theme_slug = 'graphite'"
    )

    execute("UPDATE users SET preferred_theme_slug = NULL WHERE preferred_theme_slug = 'frost'")
  end

  defp quoted(slugs), do: Enum.map_join(slugs, ", ", &"'#{&1}'")
end
