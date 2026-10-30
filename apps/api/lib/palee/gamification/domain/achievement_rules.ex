defmodule Palee.Gamification.Domain.AchievementRules do
  alias Palee.Workouts.Domain.WorkoutType

  @attendance_thresholds [1, 10, 25, 50, 100, 200, 365]
  @pr_thresholds [1, 5, 10, 25, 50]
  @streak_thresholds [7, 30, 90]
  # ADR-275: mastery badges count a workout family, so every kind in it
  # counts. The first six keys keep the original kinds' badges.
  @type_badges %{
    "functional" => {"type_crossfit_mastery", "CrossFit Devotee"},
    "strength" => {"type_strength_mastery", "Iron Lifter"},
    "gymnastics" => {"type_gymnastics_mastery", "Gymnastics Adept"},
    "endurance" => {"type_aerobics_mastery", "Cardio Machine"},
    "mind_body" => {"type_flexibility_mastery", "Flex Master"},
    "recovery" => {"type_recovery_mastery", "Recovery Pro"},
    "combat" => {"type_combat_mastery", "Fighter"},
    "dance" => {"type_dance_mastery", "Dancer"},
    "outdoor" => {"type_outdoor_mastery", "Explorer"}
  }

  def milestone_badges(stats, type_counts) do
    workout_badges =
      @attendance_thresholds
      |> Enum.filter(&((stats.total_workouts || 0) >= &1))
      |> Enum.map(&"workouts_#{&1}")

    pr_badges =
      @pr_thresholds
      |> Enum.filter(&((stats.total_prs || 0) >= &1))
      |> Enum.map(&"prs_#{&1}")

    streak_badges =
      @streak_thresholds
      |> Enum.filter(&((stats.current_streak || 0) >= &1))
      |> Enum.map(&"streak_#{&1}")

    mastery_badges =
      type_counts
      |> Enum.reduce(%{}, fn {type, count}, acc ->
        case WorkoutType.family(type) do
          nil -> acc
          family -> Map.update(acc, family, count, &(&1 + count))
        end
      end)
      |> Enum.filter(fn {_family, count} -> count >= 10 end)
      |> Enum.map(fn {family, _count} ->
        @type_badges[family] && elem(@type_badges[family], 0)
      end)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(workout_badges ++ pr_badges ++ streak_badges ++ mastery_badges)
  end

  @doc """
  «Επόμενο ορόσημο» (ADR-285): the milestone badge the person is closest to
  and has not earned yet, from the workout, PR and day-streak ladders, as
  `%{badge_key, kind, current, target, remaining}`. Closest is the largest
  share of the way done; a tie goes to the fewest steps left. Nil once every
  ladder is complete.
  """
  @spec next_milestone(map() | nil, [String.t()]) :: map() | nil
  def next_milestone(stats, earned_badge_keys \\ []) do
    stats = stats || %{}
    earned = MapSet.new(earned_badge_keys)

    [
      {"workouts", @attendance_thresholds, stat(stats, :total_workouts)},
      {"prs", @pr_thresholds, stat(stats, :total_prs)},
      {"streak", @streak_thresholds, stat(stats, :current_streak)}
    ]
    |> Enum.flat_map(fn {kind, thresholds, current} ->
      thresholds
      |> Enum.find(&(&1 > current and not MapSet.member?(earned, "#{kind}_#{&1}")))
      |> case do
        nil ->
          []

        target ->
          [
            %{
              badge_key: "#{kind}_#{target}",
              kind: kind,
              current: current,
              target: target,
              remaining: target - current
            }
          ]
      end
    end)
    |> Enum.sort_by(&{-(&1.current / &1.target), &1.remaining})
    |> List.first()
  end

  defp stat(stats, key) do
    case Map.get(stats, key) do
      value when is_integer(value) and value > 0 -> value
      _missing -> 0
    end
  end

  def visible_badge?(badge_key), do: not String.starts_with?(badge_key, "pr_event:")

  def badge_label("workouts_" <> count), do: "#{count} Workouts"
  def badge_label("prs_" <> count), do: "#{count} PRs"
  def badge_label("streak_" <> count), do: "#{count}-Week Streak"

  def badge_label(key) do
    case Enum.find(@type_badges, fn {_type, {badge_key, _label}} -> badge_key == key end) do
      {_type, {_badge_key, label}} ->
        label

      nil ->
        key
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end
end
