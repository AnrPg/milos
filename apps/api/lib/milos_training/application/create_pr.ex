defmodule MilosTraining.Application.CreatePR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.{Gamification, Pantheon}

  def call(user_id, params) do
    case Pantheon.create_record(Map.put(params, "user_id", user_id)) do
      {:ok, pr} ->
        {:ok, _stats} = Gamification.increment_advancement(user_id, DateTime.utc_now())
        :ok = PRSearchIndex.enqueue_upsert(pr)
        InvalidateLandingPages.for_users([user_id])
        {:ok, pr}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
