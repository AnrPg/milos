defmodule MilosTraining.Repo.Migrations.ScopeRemainingT4UniqueIndexes do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:messaging_threads, [:direct_key],
                     name: :messaging_threads_direct_key_index
                   )

    create unique_index(:messaging_threads, [:organization_id, :direct_key],
             name: :messaging_threads_organization_direct_key_index,
             where: "direct_key IS NOT NULL"
           )

    drop_if_exists unique_index(:messaging_threads, [:context_type, :context_id],
                     name: :messaging_threads_context_unique
                   )

    create unique_index(:messaging_threads, [:organization_id, :context_type, :context_id],
             name: :messaging_threads_organization_context_index,
             where: "context_type != 'direct'"
           )

    drop_if_exists unique_index(:communication_threads, [:context_type, :context_id],
                     name: :communication_threads_context_type_context_id_index
                   )

    create unique_index(:communication_threads, [:organization_id, :context_type, :context_id],
             name: :communication_threads_organization_context_index
           )

    drop_if_exists unique_index(:user_challenge_progress, [:user_id, :challenge_id])

    create unique_index(:user_challenge_progress, [:organization_id, :user_id, :challenge_id],
             name: :user_challenge_progress_organization_user_challenge_index
           )

    drop_if_exists unique_index(:leaderboard_opt_ins, [:user_id])

    create unique_index(:leaderboard_opt_ins, [:organization_id, :user_id],
             name: :leaderboard_opt_ins_organization_user_index
           )

    drop_if_exists unique_index(:challenge_leaderboard_opt_ins, [:user_id, :challenge_id])

    create unique_index(
             :challenge_leaderboard_opt_ins,
             [:organization_id, :user_id, :challenge_id],
             name: :challenge_leaderboard_opt_ins_organization_user_challenge_index
           )
  end

  def down do
    drop_if_exists unique_index(
                     :challenge_leaderboard_opt_ins,
                     [
                       :organization_id,
                       :user_id,
                       :challenge_id
                     ],
                     name: :challenge_leaderboard_opt_ins_organization_user_challenge_index
                   )

    create unique_index(:challenge_leaderboard_opt_ins, [:user_id, :challenge_id])

    drop_if_exists unique_index(:leaderboard_opt_ins, [:organization_id, :user_id],
                     name: :leaderboard_opt_ins_organization_user_index
                   )

    create unique_index(:leaderboard_opt_ins, [:user_id])

    drop_if_exists unique_index(
                     :user_challenge_progress,
                     [
                       :organization_id,
                       :user_id,
                       :challenge_id
                     ],
                     name: :user_challenge_progress_organization_user_challenge_index
                   )

    create unique_index(:user_challenge_progress, [:user_id, :challenge_id])

    drop_if_exists unique_index(
                     :communication_threads,
                     [
                       :organization_id,
                       :context_type,
                       :context_id
                     ],
                     name: :communication_threads_organization_context_index
                   )

    create unique_index(:communication_threads, [:context_type, :context_id],
             name: :communication_threads_context_type_context_id_index
           )

    drop_if_exists unique_index(
                     :messaging_threads,
                     [:organization_id, :context_type, :context_id],
                     name: :messaging_threads_organization_context_index
                   )

    create unique_index(:messaging_threads, [:context_type, :context_id],
             name: :messaging_threads_context_unique,
             where: "context_type != 'direct'"
           )

    drop_if_exists unique_index(:messaging_threads, [:organization_id, :direct_key],
                     name: :messaging_threads_organization_direct_key_index
                   )

    create unique_index(:messaging_threads, [:direct_key],
             name: :messaging_threads_direct_key_index,
             where: "direct_key IS NOT NULL"
           )
  end
end
