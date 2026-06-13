defmodule MilosTraining.Repo.Migrations.AddLastIncrementEventToUserChallengeProgress do
  use Ecto.Migration

  def change do
    alter table(:user_challenge_progress) do
      add :last_increment_event, :map, default: nil
    end
  end
end
