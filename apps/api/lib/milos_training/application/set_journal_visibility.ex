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

  alias MilosTraining.Application.{
    BroadcastUserSync,
    JournalAudience,
    JournalEntryLookup,
    RequestCoachReply
  }

  alias MilosTraining.{Devices, Execution, Journal, Pantheon, Wellbeing, Wellness}

  def call(%{user_id: user_id} = context, kind, id, params) do
    rung = param(params, "visibility")

    Journal.with_context(context, fn ->
      Journal.transaction(fn ->
        with {:ok, entry} <- JournalEntryLookup.fetch(kind, id, user_id),
             {:ok, audience} <- maybe_store_audience(context, kind, entry, params),
             :ok <-
               Journal.validate_visibility_move(
                 kind,
                 rung,
                 JournalAudience.reach(context, kind, entry)
               ),
             {:ok, updated} <- move(kind, entry.id, user_id, rung),
             {:ok, message} <- maybe_request_reply(context, kind, entry, rung, params) do
          {:ok,
           %{
             kind: kind,
             id: updated.id,
             journal_visibility: updated.journal_visibility,
             choosable_visibilities: JournalAudience.choosable(context, kind, entry),
             audience: audience,
             reply_request: message && %{id: message.id, thread_id: message.thread_id}
           }}
        end
      end)
    end)
    |> broadcast(user_id)
  end

  # ADR-162: the move may name the entry's own audience in the same request.
  defp maybe_store_audience(context, kind, entry, params) do
    case Map.fetch(params, "audience") do
      {:ok, ids} -> JournalAudience.store_entry(context, kind, entry, ids)
      :error -> {:ok, nil}
    end
  end

  defp maybe_request_reply(context, kind, entry, "coach_reply_requested", params),
    do: RequestCoachReply.call(context, kind, entry, params)

  defp maybe_request_reply(_context, _kind, _entry, _rung, _params), do: {:ok, nil}

  defp move("execution", id, user_id, rung),
    do: Execution.set_execution_visibility(id, user_id, rung)

  defp move("training_log", id, user_id, rung),
    do: Execution.set_training_log_visibility(id, user_id, rung)

  defp move("pr", id, user_id, rung), do: Pantheon.set_record_visibility(id, user_id, rung)
  defp move("injury", id, user_id, rung), do: Wellbeing.set_injury_visibility(id, user_id, rung)
  defp move("note", id, user_id, rung), do: Journal.set_note_visibility(id, user_id, rung)

  defp move("check_in", id, user_id, rung),
    do: Wellbeing.set_check_in_visibility(id, user_id, rung)

  # ADR-159: wellness entries and cravings move one by one.
  defp move("wellness_entry", id, user_id, rung),
    do: Wellness.set_entry_visibility(Wellness.get_entry(id, user_id), rung)

  defp move("craving", id, user_id, rung),
    do: Wellness.set_craving_visibility(Wellness.get_craving(id, user_id), rung)

  defp move("device_activity", id, user_id, rung),
    do: Devices.update_activity(Devices.get_activity(id, user_id), %{journal_visibility: rung})

  defp broadcast({:ok, result} = ok, user_id) do
    BroadcastUserSync.for_user(user_id, ["my_journal"],
      reason: "journal_visibility_changed",
      payload: %{kind: result.kind, id: result.id, journal_visibility: result.journal_visibility}
    )

    ok
  end

  defp broadcast(error, _user_id), do: error

  # String or atom keys (cast params); never creates or demands an atom.
  defp param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(params, fn {k, v} -> is_atom(k) and Atom.to_string(k) == key and v end)
    end
  end
end
