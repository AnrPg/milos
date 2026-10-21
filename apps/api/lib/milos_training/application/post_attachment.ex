defmodule MilosTraining.Application.PostAttachment do
  @moduledoc """
  A journal entry attached to a post (ADR-138, ADR-139). The author shares
  exactly what the entry showed at that moment: the snapshot is stored on
  the post, so later edits stay in the journal. Attaching moves the entry to
  the `posted` rung; deleting the last post that carries it moves it back to
  the rung it had before.
  """

  alias MilosTraining.Application.ListWorkoutExecutions
  alias MilosTraining.{Execution, Journal, Pantheon}

  @doc "The snapshot of one of the user's own entries, or an error."
  def snapshot(user_id, type, id) do
    with {:ok, id} <- cast(id),
         {:ok, entry} <-
           Journal.with_context(%{user_id: user_id}, fn -> owned(type, id, user_id) end) do
      {:ok, %{attachment_type: type, attachment_id: id, attachment: present(type, entry)}}
    end
  end

  @doc """
  The card the entry would make in a post, as readers would see it
  (ADR-157: the compose prefills it, e.g. right after a PR is logged).
  """
  def preview(user_id, type, id) do
    with {:ok, snapshot} <- snapshot(user_id, type, id) do
      {:ok, Map.update!(snapshot, :attachment, &Map.delete(&1, "previous_visibility"))}
    end
  end

  @doc "Moves the attached entry to `posted`, remembering its rung on the post's snapshot."
  def mark_posted(_user_id, %{attachment_type: nil}), do: :ok

  def mark_posted(user_id, %{attachment_type: type, attachment_id: id}) do
    case in_entry_scope(user_id, type, id, fn -> move(type, id, user_id, "posted") end) do
      {:ok, _entry} -> :ok
      error -> error
    end
  end

  @doc "Moves the entry back to its rung before it was posted."
  def restore(_user_id, %{attachment_type: nil}), do: :ok

  def restore(user_id, %{attachment_type: type, attachment_id: id, attachment: snapshot}) do
    rung =
      Map.get(snapshot || %{}, "previous_visibility") ||
        Map.get(snapshot || %{}, :previous_visibility)

    if is_binary(rung) and rung != "posted" do
      in_entry_scope(user_id, type, id, fn -> move(type, id, user_id, rung) end)
    end

    :ok
  end

  # A gym entry is written in that gym's scope (its RLS checks both the owner
  # and the gym); a personal one in the owner's session.
  defp in_entry_scope(user_id, type, id, fun) do
    case Journal.with_context(%{user_id: user_id}, fn -> fetch(type, id, user_id) end) do
      nil ->
        {:error, :not_found}

      %{organization_id: organization_id} when is_binary(organization_id) ->
        Journal.with_context(%{user_id: user_id, organization_id: organization_id}, fun)

      _personal ->
        Journal.with_context(%{user_id: user_id}, fun)
    end
  end

  defp cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :attachment_not_shareable}
    end
  end

  defp owned(type, id, user_id) do
    case fetch(type, id, user_id) do
      nil ->
        {:error, :attachment_not_shareable}

      %{status: status} when status in ["voided", :voided, :abandoned, "abandoned"] ->
        {:error, :attachment_not_shareable}

      entry ->
        {:ok, entry}
    end
  end

  defp fetch("training_log_entry", id, user_id),
    do: Execution.get_training_log_entry_for_user(id, user_id)

  defp fetch("workout_execution", id, user_id) do
    case Execution.get_execution_for_user(id, user_id) do
      %{completed_at_utc: %DateTime{}} = execution ->
        execution |> List.wrap() |> ListWorkoutExecutions.summarize() |> hd()

      _unfinished ->
        nil
    end
  end

  defp fetch("pr", id, user_id), do: Pantheon.get_record_for_user(id, user_id)
  defp fetch(_type, _id, _user_id), do: nil

  defp move("training_log_entry", id, user_id, rung),
    do: Execution.set_training_log_visibility(id, user_id, rung)

  defp move("workout_execution", id, user_id, rung),
    do: Execution.set_execution_visibility(id, user_id, rung)

  defp move("pr", id, user_id, rung), do: Pantheon.set_record_visibility(id, user_id, rung)

  defp present("training_log_entry", entry) do
    %{
      "title" => entry.title,
      "workout_type" => entry.workout_type,
      "scale_level_slug" => entry.scale_level_slug,
      "occurred_at" => entry.performed_at_utc,
      "duration_seconds" => entry.duration_seconds,
      "section_scores" => entry.section_scores || [],
      "previous_visibility" => entry.journal_visibility
    }
  end

  defp present("workout_execution", execution) do
    %{
      "title" => execution.workout_title,
      "workout_type" => execution.workout_type,
      "scale_level_slug" => execution.scale_level_slug,
      "occurred_at" => execution.completed_at_utc,
      "duration_seconds" => div(execution.total_elapsed_ms || 0, 1000),
      "section_scores" => execution.section_scores || [],
      "previous_visibility" => execution.journal_visibility
    }
  end

  defp present("pr", record) do
    %{
      "title" => record.name,
      "score" => record.current_score,
      "unit" => record.unit,
      "occurred_on" => record.beaten_on,
      "previous_visibility" => record.journal_visibility
    }
  end
end
