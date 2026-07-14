defmodule MilosTraining.Gamification.Commands.CreateSeasonalChallenge do
  alias MilosTraining.Gamification.Domain.ChallengeCriteria
  alias MilosTraining.Gamification.GamificationStore

  def call(admin_id, params) do
    with {:ok, attrs} <- normalize_attrs(params, admin_id) do
      GamificationStore.create_challenge_with_limit(attrs, 3)
    end
  end

  defp normalize_attrs(params, admin_id) do
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
         ends_at: ends_at,
         created_by_id: admin_id
       }}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_value), do: {:error, :invalid_date}
end
