defmodule Palee.Application.UpdatePR do
  alias Palee.Application.{InvalidateLandingPages, JournalComments, PRSearchIndex}
  alias Palee.{Gamification, Pantheon}
  alias Palee.Pantheon.Domain.PRResultMetrics

  # Owner-only under RLS: runs in the acting user's scope (ADR-129).
  # Comments sent with the change (ADR-140 §1) are saved with it.
  def call(%{user_id: user_id} = context, id, params) do
    JournalComments.write_with_comments(
      context,
      "pr",
      params["comments"] || params[:comments],
      fn ->
        Pantheon.with_user_context(context, fn ->
          call(id, user_id, Map.drop(params, ["comments", :comments]))
        end)
      end
    )
  end

  def call(id, user_id, params) do
    case Pantheon.get_record_for_user(id, user_id) do
      nil ->
        {:error, :not_found}

      existing_pr ->
        with {:ok, normalized_params} <- normalize_params(params),
             {:ok, updated_pr} <- Pantheon.update_record(id, normalized_params) do
          if score_improved?(existing_pr, updated_pr) do
            {:ok, _stats} = Gamification.increment_advancement(user_id, DateTime.utc_now())
          end

          :ok = PRSearchIndex.enqueue_upsert(updated_pr)
          InvalidateLandingPages.for_users([user_id])
          {:ok, updated_pr}
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
