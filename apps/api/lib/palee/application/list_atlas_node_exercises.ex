defmodule Palee.Application.ListAtlasNodeExercises do
  @moduledoc """
  `GET /api/org/:slug/anatomy/nodes/:node_id/exercises` (ADR-164): the
  exercises that train an atlas node, with the gym's videos for each.

  Exercises are the Quick Text catalog entries whose primary or secondary
  targets reach the node (`Anatomy.exercises_for_node/1`). The gym has no
  per-exercise video field; its on-demand library (ADR-098) is the gym's
  exercise library, so a published video is attached to an exercise when one
  of its tags, or its whole title, names that exercise (catalog id, label or
  alias, plural-tolerant). Videos follow the library's own rule: only when
  the member's package includes on-demand videos (staff always), otherwise
  the exercises come without them and `videos_included` is false.

  Order: primary before secondary; within a role, exercises with a video
  first, then catalog id.
  """

  alias Palee.Application.AuthorizePackageFeature
  alias Palee.{Anatomy, Content, Workouts}

  def call(context, actor, node_id) do
    case Anatomy.exercises_for_node(node_id) do
      {:ok, targets} ->
        {videos_included, by_exercise} = videos(context, actor)

        exercises =
          targets
          |> Enum.map(&exercise(&1, by_exercise))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(fn exercise ->
            {exercise.role != "primary", exercise.videos == [], exercise.exercise_ref}
          end)

        {:ok, %{node_id: node_id, videos_included: videos_included, exercises: exercises}}

      :error ->
        {:error, :not_found}
    end
  end

  defp exercise(%{exercise_ref: ref, role: role}, by_exercise) do
    case Workouts.resolve_catalog_exercise(ref, nil) do
      nil ->
        nil

      entry ->
        %{
          exercise_ref: ref,
          label: entry.label,
          role: Atom.to_string(role),
          videos: Map.get(by_exercise, ref, [])
        }
    end
  end

  defp videos(context, actor) do
    case AuthorizePackageFeature.call(context, actor, :watch_on_demand) do
      :ok -> {true, index_videos(Content.list_videos(context, visibility: :members))}
      _denied -> {false, %{}}
    end
  end

  defp index_videos(videos) do
    videos
    |> Enum.flat_map(fn video ->
      [video.title | video.tags || []]
      |> Enum.map(&Workouts.resolve_catalog_exercise(nil, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Enum.map(&{&1, summary(video)})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp summary(video) do
    %{
      id: video.id,
      title: video.title,
      video_url: video.video_url,
      duration_minutes: video.duration_minutes
    }
  end
end
