defmodule MilosTraining.Application.SuggestWorkoutIcon do
  @moduledoc """
  Gives a freshly published workout a fitting emoji using the configured
  suggester (Gemini, ADR-136). Runs in the background after publishing and never
  overrides an icon a coach picked. Failures are silent: the library's keyword
  rules keep showing an icon.
  """

  require Logger

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Organizations, Workouts}
  alias MilosTraining.Workers.SuggestWorkoutIconJob
  alias MilosTraining.Workouts.Domain.WorkoutIcon

  @max_movements 20

  @doc "Schedules a suggestion (inline when background jobs are disabled, e.g. in tests)."
  def enqueue(%{organization_id: organization_id} = context, workout_id) do
    if Application.get_env(:milos_training, :start_oban, true) do
      %{"organization_id" => organization_id, "workout_id" => workout_id}
      |> SuggestWorkoutIconJob.new()
      |> Oban.insert()

      :ok
    else
      _result = call(context, workout_id)
      :ok
    end
  end

  def enqueue(_context, _workout_id), do: :ok

  def call(context, workout_id) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      %{icon_source: "coach"} -> {:ok, :kept_coach_icon}
      %{status: "published"} = workout -> suggest(context, workout)
      _missing_or_draft -> {:ok, :skipped}
    end
  end

  defp suggest(context, workout) do
    with {:ok, raw} <- suggester().suggest(summary(workout), metering(context)),
         {:ok, icon} <- validate(raw),
         {:ok, _updated} <- Workouts.set_workout_icon(context, workout.id, icon, "ai") do
      broadcast_refresh(context, workout.id)
      {:ok, icon}
    else
      {:error, :not_configured} ->
        {:ok, :not_configured}

      {:error, reason} ->
        Logger.info(
          "workout_icon_suggestion_skipped workout_id=#{workout.id} reason=#{inspect(reason)}"
        )

        {:ok, :skipped}
    end
  end

  defp validate(raw) do
    case WorkoutIcon.normalize(raw) do
      {:ok, icon} -> {:ok, icon}
      :error -> {:error, :not_a_single_emoji}
    end
  end

  defp summary(workout) do
    sections = List.wrap(workout[:sections])

    %{
      title: workout[:title] || "",
      type: workout[:type] && to_string(workout[:type]),
      description: workout[:description] || workout[:free_text_body],
      sections: sections |> Enum.map(&field(&1, :name)) |> Enum.filter(&is_binary/1),
      movements:
        sections
        |> Enum.flat_map(&List.wrap(field(&1, :exercises)))
        |> Enum.map(&field(&1, :name))
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
        |> Enum.take(@max_movements)
    }
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(_value, _key), do: nil

  defp broadcast_refresh(%{organization_id: organization_id}, workout_id) do
    organization_id
    |> Organizations.list_staff_user_ids()
    |> BroadcastUserSync.for_users(["admin_workouts"],
      reason: "workout_icon_suggested",
      payload: %{workout_id: workout_id}
    )
  end

  # ADR-152: one suggestion is one metered operation of the gym.
  defp metering(context) do
    %{
      organization_id: Map.get(context, :organization_id),
      user_id: Map.get(context, :user_id),
      operation_id: Ecto.UUID.generate(),
      feature: "workout_icon"
    }
  end

  defp suggester, do: Application.fetch_env!(:milos_training, :workout_icon_suggester)
end
