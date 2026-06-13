defmodule MilosTraining.Repo.Migrations.CreateChallengeLeaderboardOptIns do
  use Ecto.Migration

  def change do
    create table(:challenge_leaderboard_opt_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :challenge_id, references(:seasonal_challenges, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:challenge_leaderboard_opt_ins, [:user_id, :challenge_id])
    create index(:challenge_leaderboard_opt_ins, [:challenge_id])
  end
end
