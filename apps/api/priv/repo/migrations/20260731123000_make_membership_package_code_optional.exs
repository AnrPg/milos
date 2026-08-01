defmodule MilosTraining.Repo.Migrations.MakeMembershipPackageCodeOptional do
  use Ecto.Migration

  def change do
    alter table(:membership_packages) do
      modify :code, :string, null: true
    end
  end
end
