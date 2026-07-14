defmodule MilosTraining.Gamification.Domain.AchievementRules do
  @attendance_thresholds [1, 10, 25, 50, 100, 200, 365]
  @pr_thresholds [1, 5, 10, 25, 50]
  @streak_thresholds [7, 30, 90]
  @type_badges %{
    "crossfit" => {"type_crossfit_mastery", "CrossFit Devotee"},
    "strength" => {"type_strength_mastery", "Iron Lifter"},
    "gymnastics" => {"type_gymnastics_mastery", "Gymnastics Adept"},
    "aerobics" => {"type_aerobics_mastery", "Cardio Machine"},
    "flexibility" => {"type_flexibility_mastery", "Flex Master"},
    "recovery" => {"type_recovery_mastery", "Recovery Pro"}
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
      |> Enum.filter(fn {_type, count} -> count >= 10 end)
      |> Enum.map(fn {type, _count} -> @type_badges[type] && elem(@type_badges[type], 0) end)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(workout_badges ++ pr_badges ++ streak_badges ++ mastery_badges)
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
