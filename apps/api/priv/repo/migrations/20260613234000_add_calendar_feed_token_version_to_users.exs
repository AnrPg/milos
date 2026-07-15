defmodule MilosTraining.Repo.Migrations.AddCalendarFeedTokenVersionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :calendar_feed_token_version, :integer, null: false, default: 1
    end
  end
end
