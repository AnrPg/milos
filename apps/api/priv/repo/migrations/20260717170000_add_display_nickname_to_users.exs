defmodule MilosTraining.Repo.Migrations.AddDisplayNicknameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :display_nickname, :string
    end

    execute("UPDATE users SET display_nickname = nickname WHERE display_nickname IS NULL")

    alter table(:users) do
      modify :display_nickname, :string, null: false
    end
  end

  def down do
    alter table(:users) do
      remove :display_nickname
    end
  end
end
