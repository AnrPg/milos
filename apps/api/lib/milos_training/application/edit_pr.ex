defmodule MilosTraining.Application.EditPR do
  alias MilosTraining.Application.{InvalidateLandingPages, PRSearchIndex}
  alias MilosTraining.Pantheon
  alias MilosTraining.Pantheon.Domain.PRResultMetrics

  def call(id, user_id, params) do
    case Pantheon.get_record_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      _existing_pr ->
        with {:ok, normalized_params} <- normalize_params(params),
             {:ok, edited_pr} <- Pantheon.edit_record(id, normalized_params) do
          :ok = PRSearchIndex.enqueue_upsert(edited_pr)
          InvalidateLandingPages.for_users([user_id])
          {:ok, edited_pr}
        end
    end
  end

  defp normalize_params(params) do
    has_metrics? =
      Map.has_key?(params, "supporting_metrics") || Map.has_key?(params, :supporting_metrics)

    if has_metrics? do
      with {:ok, metrics} <-
             PRResultMetrics.normalize(
               params["supporting_metrics"] || params[:supporting_metrics]
             ) do
        {:ok, Map.put(params, "supporting_metrics", metrics)}
      end
    else
      {:ok, params}
    end
  end
end
