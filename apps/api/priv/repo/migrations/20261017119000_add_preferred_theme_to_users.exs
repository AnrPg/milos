defmodule Palee.Repo.Migrations.AddPreferredThemeToUsers do
  use Ecto.Migration

  # Ρυθμίσεις › Θέμα: a member's own theme; NULL follows their gym's theme.
  def change do
    alter table(:users) do
      add :preferred_theme_slug, :string
    end
  end
end
