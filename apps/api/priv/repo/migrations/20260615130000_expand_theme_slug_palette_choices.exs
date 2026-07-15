defmodule MilosTraining.Repo.Migrations.ExpandThemeSlugPaletteChoices do
  use Ecto.Migration

  @constraint_name :gamification_settings_theme_slug_check
  @theme_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

  def up do
    drop constraint(:gamification_settings, @constraint_name)

    create constraint(
             :gamification_settings,
             @constraint_name,
             check: "theme_slug IN (#{quoted_slugs(@theme_slugs)})"
           )
  end

  def down do
    execute(
      "UPDATE gamification_settings SET theme_slug = 'ember' WHERE theme_slug NOT IN ('ember', 'sage', 'steel')"
    )

    drop constraint(:gamification_settings, @constraint_name)

    create constraint(
             :gamification_settings,
             @constraint_name,
             check: "theme_slug IN ('ember', 'sage', 'steel')"
           )
  end

  defp quoted_slugs(slugs) do
    slugs
    |> Enum.map_join(", ", &"'#{&1}'")
  end
end
