defmodule MilosTraining.Repo.Migrations.AddThemeSlugToGamificationSettings do
  use Ecto.Migration

  def change do
    alter table(:gamification_settings) do
      add :theme_slug, :string, null: false, default: "ember"
    end

    create constraint(
             :gamification_settings,
             :gamification_settings_theme_slug_check,
             check: "theme_slug IN ('ember', 'sage', 'steel')"
           )
  end
end
