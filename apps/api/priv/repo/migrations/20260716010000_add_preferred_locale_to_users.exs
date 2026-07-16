defmodule MilosTraining.Repo.Migrations.AddPreferredLocaleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferred_locale, :string, null: false, default: "en"
    end

    create constraint(:users, :users_preferred_locale_supported,
             check:
               "preferred_locale IN ('en', 'el', 'ar', 'ru', 'de', 'es', 'pt-PT', 'he', 'it', 'bg', 'nl', 'fr')"
           )
  end
end
