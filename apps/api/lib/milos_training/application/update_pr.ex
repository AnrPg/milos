defmodule MilosTraining.Application.UpdatePR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.{Gamification, Pantheon}

  def call(id, user_id, params) do
    case Pantheon.get_record_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      existing_pr ->
        case Pantheon.update_record(id, params) do
          {:ok, updated_pr} ->
            if score_improved?(existing_pr, updated_pr) do
              {:ok, _stats} = Gamification.increment_advancement(user_id, DateTime.utc_now())
            end

            :ok = PRSearchIndex.enqueue_upsert(updated_pr)
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
end
