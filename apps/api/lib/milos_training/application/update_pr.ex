defmodule MilosTraining.Application.UpdatePR do
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Gamification.GamificationStore
  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex
  alias MilosTraining.Pantheon.PRStore

  def call(id, user_id, params) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      existing_pr ->
        case PRStore.update_pr(id, params) do
          {:ok, updated_pr} ->
            if score_improved?(existing_pr, updated_pr) do
              increment_advancement(user_id)
            end

            Task.start(fn -> MeilisearchPRIndex.upsert_document(updated_pr) end)
            InvalidateLandingPages.for_users([user_id])
            {:ok, updated_pr}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp score_improved?(old_pr, new_pr) do
    old_score = old_pr[:current_score] || 0
    new_score = new_pr[:current_score] || 0

    if old_pr[:higher_is_better] do
      new_score > old_score
    else
      new_score < old_score
    end
  end

  defp increment_advancement(user_id) do
    existing = GamificationStore.get_user_stats(user_id) || %{advancement_count: 0}
    current = existing[:advancement_count] || 0

    GamificationStore.upsert_user_stats(%{
      user_id: user_id,
      advancement_count: current + 1,
      updated_at: DateTime.utc_now()
    })
  end
end
