defmodule MilosTraining.Application.CreatePR do
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Gamification.GamificationStore
  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex
  alias MilosTraining.Pantheon.PRStore

  def call(user_id, params) do
    case PRStore.create_pr(Map.put(params, "user_id", user_id)) do
      {:ok, pr} ->
        increment_advancement(user_id)
        Task.start(fn -> MeilisearchPRIndex.upsert_document(pr) end)
        InvalidateLandingPages.for_users([user_id])
        {:ok, pr}

      {:error, changeset} ->
        {:error, changeset}
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
