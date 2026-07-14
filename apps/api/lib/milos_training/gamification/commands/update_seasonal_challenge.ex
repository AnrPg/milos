defmodule MilosTraining.Gamification.Commands.UpdateSeasonalChallenge do
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeSchedulePolicy}
  alias MilosTraining.Gamification.GamificationStore

  def call(id, params) do
    with challenge when not is_nil(challenge) <- GamificationStore.get_challenge(id),
         {:ok, attrs} <- normalize_attrs(params),
         :ok <-
           challenge_schedule(challenge.id, attrs.starts_at, attrs.ends_at) do
      GamificationStore.update_challenge(id, attrs)
    else
      nil -> {:error, :not_found}
    end
  end

  defp normalize_attrs(params) do
    with {:ok, starts_at} <- parse_date(params[:starts_at] || params["starts_at"]),
         {:ok, ends_at} <- parse_date(params[:ends_at] || params["ends_at"]),
         {:ok, normalized_criteria} <-
           ChallengeCriteria.normalize(
             params[:criteria_type] || params["criteria_type"],
             params[:criteria_value] || params["criteria_value"] || %{}
           ) do
      {:ok,
       %{
         title: params[:title] || params["title"],
         description: params[:description] || params["description"],
         criteria_type: normalized_criteria.criteria_type,
         criteria_value: normalized_criteria.criteria_value,
         badge_key: params[:badge_key] || params["badge_key"],
         badge_label: params[:badge_label] || params["badge_label"],
         starts_at: starts_at,
         ends_at: ends_at
       }}
    end
  end

  defp challenge_schedule(current_id, starts_at, ends_at) do
    GamificationStore.list_challenges()
    |> Enum.reject(&(&1.id == current_id))
    |> ChallengeSchedulePolicy.validate_max_active(starts_at, ends_at)
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_value), do: {:error, :invalid_date}
end
