defmodule Palee.Workouts.Domain.WorkoutFocus do
  @moduledoc """
  What a workout trains, read from its movements (Phase 2 Πρόγραμμα filter
  «Εστίαση προπόνησης»): a modality (`strength`, `endurance`, `gymnastics`,
  `olympic_lifting`, `mobility`) and a body region (`legs`, `core`,
  `upper_body`).

  Each movement resolved to the exercise catalog (via `ExerciseDescriptors`)
  carries tags. A workout has a focus when at least a third of its resolved
  movements carry it, so one sit-up in a leg day does not make it a core day.
  Olympic lifts are the exception: any snatch, clean or jerk makes the session
  an olympic lifting one, because that is what members plan around.
  Unresolved movements are ignored; a workout with none resolved has no focus.
  """

  alias Palee.Workouts.Domain.ExerciseDescriptors

  @focuses ~w(strength endurance gymnastics olympic_lifting mobility legs core upper_body)

  @olympic ~w(
    clean power-clean hang-clean clean-and-jerk snatch power-snatch hang-snatch
    muscle-snatch jerk push-jerk
  )

  @gymnastics ~w(
    pistol-squat push-up hand-release-push-up diamond-push-up dip ring-dip pull-up
    strict-pull-up chest-to-bar-pull-up chin-up ring-row toes-to-bar knees-to-elbows
    ghd-sit-up back-extension
  )

  @legs ~w(
    air-squat back-squat front-squat overhead-squat goblet-squat box-squat split-squat
    bulgarian-split-squat pistol-squat wall-sit deadlift sumo-deadlift romanian-deadlift
    stiff-leg-deadlift single-leg-deadlift clean power-clean hang-clean clean-and-jerk snatch
    power-snatch hang-snatch good-morning hip-thrust glute-bridge lunge reverse-lunge
    walking-lunge step-up calf-raise sled-push kettlebell-swing american-kettlebell-swing
    russian-kettlebell-swing thruster wall-ball box-jump box-jump-over broad-jump
    burpee-box-jump run sprint bike air-bike stair-climb hip-flexor-stretch
    hamstring-stretch quad-stretch calf-stretch pigeon-stretch couch-stretch
  )

  @core ~w(
    toes-to-bar knees-to-elbows sit-up ghd-sit-up v-up hollow-hold arch-hold plank
    side-plank pallof-press back-extension turkish-get-up farmer-carry front-rack-carry
    overhead-carry
  )

  @upper_body ~w(
    overhead-squat snatch power-snatch hang-snatch muscle-snatch jerk push-jerk push-press
    strict-press bench-press incline-bench-press floor-press dumbbell-bench-press dumbbell-row
    barbell-row pendlay-row upright-row biceps-curl triceps-extension skull-crusher
    lateral-raise front-raise face-pull overhead-carry sled-pull thruster wall-ball
    devil-press man-maker push-up hand-release-push-up diamond-push-up dip ring-dip pull-up
    strict-pull-up chest-to-bar-pull-up chin-up ring-row muscle-up ring-muscle-up
    bar-muscle-up rope-climb legless-rope-climb handstand-hold handstand-walk
    handstand-push-up wall-walk row ski-erg swim shoulder-dislocate band-pull-apart
    thoracic-rotation
  )

  @share_threshold 1 / 3

  @doc "The workout's focus tags, in the order listed above."
  def from_workout(workout) do
    tagged =
      workout
      |> ExerciseDescriptors.from_workout()
      |> Enum.filter(& &1.exercise_ref)
      |> Enum.map(&tags/1)

    total = length(tagged)

    counts = tagged |> List.flatten() |> Enum.frequencies()

    Enum.filter(@focuses, fn focus ->
      count = Map.get(counts, focus, 0)

      cond do
        count == 0 -> false
        focus == "olympic_lifting" -> true
        true -> count / total >= @share_threshold
      end
    end)
  end

  defp tags(%{exercise_ref: ref, category: category}) do
    [
      modality(ref, category),
      ref in @legs && "legs",
      ref in @core && "core",
      ref in @upper_body && "upper_body"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp modality(ref, _category) when ref in @olympic, do: "olympic_lifting"
  defp modality(ref, _category) when ref in @gymnastics, do: "gymnastics"
  defp modality(_ref, "skill"), do: "gymnastics"
  defp modality(_ref, "strength"), do: "strength"
  defp modality(_ref, "cardio"), do: "endurance"
  defp modality(_ref, "mobility"), do: "mobility"
  # Remaining bodyweight conditioning (burpees, box jumps, sit-ups) is engine work.
  defp modality(_ref, "bodyweight"), do: "endurance"
  defp modality(_ref, _category), do: nil
end
