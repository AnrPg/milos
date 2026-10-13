defmodule MilosTraining.Repo.Migrations.AddCompletedToursToUsers do
  use Ecto.Migration

  # Additive: which product tours (admin, member, athlete) an account has
  # finished, so the first-visit tour follows the account across devices.
  def change do
    alter table(:users) do
      add :completed_tours, {:array, :string}, null: false, default: []
    end
  end
end
