defmodule MilosTraining.Application.SetJournalVisibility do
  @moduledoc """
  Moves one of the member's journal entries on the ladder (ADR-139 §9,
  `PUT /api/me/journal/entries/:kind/:id/visibility`).

  The member picks `private`, `coach_can_view` or `coach_reply_requested`
  (what the kind allows; a personal entry only `private`). Ζητάω απάντηση also
  needs a question, which goes to the member's coach as a message about the
  entry (`RequestCoachReply`); the move and the message happen together.
  Reviews are their own rung and do not move.
  """

  alias MilosTraining.Application.{BroadcastUserSync, RequestCoachReply}
  alias MilosTraining.{Execution, Journal, Pantheon, Wellbeing}

  def call(%{user_id: user_id} = context, kind, id, params) do
    rung = param(params, "visibility")

    Journal.with_context(context, fn ->
      Journal.transaction(fn ->
        with {:ok, entry} <- fetch(kind, id, user_id),
             :ok <-
               Journal.validate_visibility_move(kind, rung, is_binary(entry.organization_id)),
             {:ok, updated} <- move(kind, entry.id, user_id, rung),
             {:ok, message} <- maybe_request_reply(context, kind, entry, rung, params) do
          {:ok,
           %{
             kind: kind,
             id: updated.id,
             journal_visibility: updated.journal_visibility,
             choosable_visibilities: Journal.choosable_visibilities(kind, entry.organization_id),
             reply_request: message && %{id: message.id, thread_id: message.thread_id}
           }}
        end
      end)
    end)
    |> broadcast(user_id)
  end

  defp maybe_request_reply(context, kind, entry, "coach_reply_requested", params),
    do: RequestCoachReply.call(context, kind, entry, params)

  defp maybe_request_reply(_context, _kind, _entry, _rung, _params), do: {:ok, nil}

  defp fetch(kind, id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> kind |> owned(id, user_id) |> found()
      :error -> {:error, :not_found}
    end
  end

  defp owned("execution", id, user_id), do: Execution.get_execution_for_user(id, user_id)

  defp owned("training_log", id, user_id),
    do: Execution.get_training_log_entry_for_user(id, user_id)

  defp owned("pr", id, user_id), do: Pantheon.get_record_for_user(id, user_id)
  defp owned("injury", id, user_id), do: Wellbeing.get_injury_for_user(user_id, id)
  defp owned("note", id, user_id), do: Journal.get_note_for_user(id, user_id)
  defp owned("check_in", id, user_id), do: Wellbeing.get_check_in_for_user(id, user_id)
  defp owned("review", _id, _user_id), do: {:error, :visibility_not_allowed}
  # ADR-158: a snapshot's visibility is set on the snapshot (Σώμα).
  defp owned("body", _id, _user_id), do: {:error, :visibility_not_allowed}
  defp owned(_kind, _id, _user_id), do: {:error, :unknown_kind}

  defp found({:error, _reason} = error), do: error
  defp found(nil), do: {:error, :not_found}
  defp found(entry), do: {:ok, entry}

  defp move("execution", id, user_id, rung),
    do: Execution.set_execution_visibility(id, user_id, rung)

  defp move("training_log", id, user_id, rung),
    do: Execution.set_training_log_visibility(id, user_id, rung)

  defp move("pr", id, user_id, rung), do: Pantheon.set_record_visibility(id, user_id, rung)
  defp move("injury", id, user_id, rung), do: Wellbeing.set_injury_visibility(id, user_id, rung)
  defp move("note", id, user_id, rung), do: Journal.set_note_visibility(id, user_id, rung)

  defp move("check_in", id, user_id, rung),
    do: Wellbeing.set_check_in_visibility(id, user_id, rung)

  defp broadcast({:ok, result} = ok, user_id) do
    BroadcastUserSync.for_user(user_id, ["my_journal"],
      reason: "journal_visibility_changed",
      payload: %{kind: result.kind, id: result.id, journal_visibility: result.journal_visibility}
    )

    ok
  end

  defp broadcast(error, _user_id), do: error

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))
end
