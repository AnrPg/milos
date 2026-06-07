defmodule MilosTraining.Repo.Migrations.AddUsersRoleConstraint do
  use Ecto.Migration

  def change do
    create constraint(:users, :users_role_must_be_valid,
             check: "role in ('member', 'athlete', 'admin')"
           )
  end
end
