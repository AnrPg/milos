defmodule MilosTraining.Gamification.Domain.ChallengeProgress do
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeRule}

  def advance(challenge, progress, completion_facts) do
    {increment, events} = evaluate(challenge, completion_facts)
    target = target(challenge)
    next_progress = progress + increment

    %{
      increment: increment,
      events: events,
      progress: next_progress,
      target: target,
      completed?: target > 0 and next_progress >= target
    }
  end

  def target(challenge), do: ChallengeCriteria.target(challenge)

  defp evaluate(%{criteria_type: type, criteria_value: cv} = challenge, facts)
       when type in ["custom", :custom] do
    if ChallengeCriteria.has_rules?(cv) do
      rules = ChallengeCriteria.rules(cv)
      resolved = resolve_team_count(facts, challenge)

      events =
        Enum.flat_map(rules, fn rule ->
          case ChallengeRule.evaluate(rule, resolved) do
            0 -> []
            pts -> [%{points: pts, label: ChallengeRule.label(rule)}]
          end
        end)

      total = Enum.reduce(events, 0, fn %{points: p}, acc -> acc + p end)
      {total, events}
    else
      pts = ChallengeCriteria.increment_per_completion(%{criteria_value: cv})
      lbl = ChallengeCriteria.increment_label(%{criteria_value: cv}) || "for this workout"
      events = if pts > 0, do: [%{points: pts, label: lbl}], else: []
      {pts, events}
    end
  end

  defp evaluate(%{criteria_type: type}, _facts)
       when type in ["workout_count", :workout_count],
       do: {1, []}

  defp evaluate(%{criteria_type: type, criteria_value: cv}, %{workout_type: wt})
       when type in ["workout_type_count", :workout_type_count] do
    filter = Map.get(cv || %{}, "type_filter") || Map.get(cv || %{}, :type_filter)
    if to_string(filter) == to_string(wt), do: {1, []}, else: {0, []}
  end

  defp evaluate(%{criteria_type: type}, %{pr_count: pr_count})
       when type in ["pr_count", :pr_count],
       do: {pr_count, []}

  defp evaluate(_challenge, _facts), do: {0, []}

  defp resolve_team_count(%{team_workout_count_fn: fun} = facts, challenge)
       when is_function(fun, 1) do
    Map.put(facts, :team_workout_count, fun.(challenge))
  end

  defp resolve_team_count(facts, _challenge), do: facts
end
