defmodule Palee.Repo.Migrations.AddPaleeBrandThemes do
  use Ecto.Migration

  # The Palee brand palette arrives as two themes: "frost" (light, the new
  # default) and "graphite" (dark). Gyms still on the old default "ember"
  # move to "frost" so the whole platform wears the brand; a gym can pick any
  # other theme again in its settings.
  @constraint_name :gamification_settings_theme_slug_check
  @old_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)
  @new_slugs ~w(frost graphite) ++ @old_slugs

  def up do
    drop constraint(:gamification_settings, @constraint_name)

    create constraint(:gamification_settings, @constraint_name,
             check: "theme_slug IN (#{quoted(@new_slugs)})"
           )

    execute("ALTER TABLE gamification_settings ALTER COLUMN theme_slug SET DEFAULT 'frost'")
    execute("UPDATE gamification_settings SET theme_slug = 'frost' WHERE theme_slug = 'ember'")
  end

  def down do
    execute(
      "UPDATE gamification_settings SET theme_slug = 'ember' WHERE theme_slug IN ('frost', 'graphite')"
    )

    execute(
      "UPDATE users SET preferred_theme_slug = NULL WHERE preferred_theme_slug IN ('frost', 'graphite')"
    )

    execute("ALTER TABLE gamification_settings ALTER COLUMN theme_slug SET DEFAULT 'ember'")
    drop constraint(:gamification_settings, @constraint_name)

    create constraint(:gamification_settings, @constraint_name,
             check: "theme_slug IN (#{quoted(@old_slugs)})"
           )
  end

  defp quoted(slugs), do: Enum.map_join(slugs, ", ", &"'#{&1}'")
end
