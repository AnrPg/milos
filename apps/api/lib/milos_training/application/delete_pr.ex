defmodule MilosTraining.Application.DeletePR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.Pantheon

  def call(id, user_id) do
    case Pantheon.delete_record(id, user_id) do
      :ok ->
        :ok = PRSearchIndex.enqueue_delete(id)
        InvalidateLandingPages.for_users([user_id])
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
