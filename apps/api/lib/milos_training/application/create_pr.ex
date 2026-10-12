defmodule MilosTraining.Application.CreatePR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.{Gamification, Pantheon}
  alias MilosTraining.Pantheon.Domain.PRResultMetrics

  def call(user_id, params) do
    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, pr} <- Pantheon.create_record(Map.put(normalized_params, "user_id", user_id)) do
      {:ok, _stats} = Gamification.increment_advancement(user_id, DateTime.utc_now())
      :ok = PRSearchIndex.enqueue_upsert(pr)
      InvalidateLandingPages.for_users([user_id])
      {:ok, pr}
    end
  end

  # Creation always requires supporting metrics, so they are normalized
  # unconditionally (an absent value is validated by PRResultMetrics).
  defp normalize_params(params) do
    with {:ok, metrics} <-
           PRResultMetrics.normalize(params["supporting_metrics"] || params[:supporting_metrics]) do
      {:ok, Map.put(params, "supporting_metrics", metrics)}
    end
  end
end
