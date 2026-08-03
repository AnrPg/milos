defmodule MilosTraining.Repo.Migrations.AllowAdminUserAccountDeletion do
  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      modify :created_by_id,
             references(:users, type: :binary_id, on_delete: :nilify_all),
             from: references(:users, type: :binary_id, on_delete: :nothing),
             null: true
    end

    alter table(:workout_folders) do
      modify :created_by_id,
             references(:users, type: :binary_id, on_delete: :nilify_all),
             from: references(:users, type: :binary_id, on_delete: :restrict),
             null: true
    end

    alter table(:seasonal_challenges) do
      modify :created_by_id,
             references(:users, type: :binary_id, on_delete: :nilify_all),
             from: references(:users, type: :binary_id, on_delete: :nothing),
             null: true
    end

    alter table(:messaging_threads) do
      modify :created_by_id,
             references(:users, type: :binary_id, on_delete: :delete_all),
             from: references(:users, type: :binary_id, on_delete: :nothing)
    end

    alter table(:messaging_participants) do
      modify :user_id,
             references(:users, type: :binary_id, on_delete: :delete_all),
             from: references(:users, type: :binary_id, on_delete: :nothing)
    end

    alter table(:messaging_messages) do
      modify :sender_id,
             references(:users, type: :binary_id, on_delete: :delete_all),
             from: references(:users, type: :binary_id, on_delete: :nothing)
    end
  end
end
