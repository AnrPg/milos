defmodule MilosTraining.Gamification.Domain.ChallengeRule do
  @doc "Returns `points` if the rule's condition is met, 0 otherwise."
  def evaluate(%{"condition" => "workout_type", "type" => type, "points" => points}, facts) do
    if to_string(Map.get(facts, :workout_type)) == to_string(type), do: points, else: 0
  end

  def evaluate(%{"condition" => "scale_level", "slug" => slug, "points" => points}, facts) do
    if to_string(Map.get(facts, :scale_level_slug)) == to_string(slug), do: points, else: 0
  end

  def evaluate(%{"condition" => "pr_beaten", "points" => points}, facts) do
    if Map.get(facts, :pr_count, 0) > 0, do: points, else: 0
  end

  def evaluate(
        %{"condition" => "weekly_consistency", "threshold" => threshold, "points" => points},
        facts
      ) do
    score = Map.get(facts, :consistency_score, 0.0)
    if score * 100 >= threshold, do: points, else: 0
  end

  def evaluate(%{"condition" => "rare_workout_type", "points" => points} = rule, facts) do
    threshold_pct = Map.get(rule, "threshold_pct", 10)
    prev = Map.get(facts, :prev_type_count, 0)
    total = Map.get(facts, :total_prev_completions, 0)
    ratio = if total == 0, do: 0.0, else: prev / total * 100
    if ratio < threshold_pct, do: points, else: 0
  end

  def evaluate(
        %{"condition" => "team_workout_streak", "min_count" => min_count, "points" => points},
        facts
      ) do
    count = Map.get(facts, :team_workout_count, 0)
    if count >= min_count, do: points, else: 0
  end

  def evaluate(_rule, _facts), do: 0

  @doc "Returns the display label for this rule's earned points."
  def label(%{"label" => lbl}) when is_binary(lbl) and lbl != "", do: lbl
  def label(rule), do: default_label(rule)

  defp default_label(%{"condition" => "workout_type", "type" => type}),
    do: "for a #{type} workout"

  defp default_label(%{"condition" => "scale_level", "slug" => slug}),
    do: "for #{slug} performance"

  defp default_label(%{"condition" => "pr_beaten"}), do: "for beating a PR"
  defp default_label(%{"condition" => "weekly_consistency"}), do: "for weekly consistency"

  defp default_label(%{"condition" => "rare_workout_type"}),
    do: "for exploring a new workout type"

  defp default_label(%{"condition" => "team_workout_streak"}), do: "for team participation"
  defp default_label(_), do: "for this workout"
end
