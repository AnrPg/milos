defmodule MilosTraining.Application.JournalEntryLookup do
  @moduledoc "One of the member's journal entries by kind and id, as its own context reads it."

  alias MilosTraining.{Devices, Execution, Journal, Pantheon, Wellbeing, Wellness}

  def fetch(kind, id, user_id) do
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
  defp owned("wellness", _id, _user_id), do: {:error, :visibility_not_allowed}
  defp owned("wellness_entry", id, user_id), do: Wellness.get_entry(id, user_id)
  defp owned("craving", id, user_id), do: Wellness.get_craving(id, user_id)
  defp owned("review", _id, _user_id), do: {:error, :visibility_not_allowed}
  # ADR-158: a snapshot's visibility is set on the snapshot (Σώμα).
  defp owned("body", _id, _user_id), do: {:error, :visibility_not_allowed}
  # ADR-161: a watch workout of its own (merged numbers follow their entry).
  defp owned("device_activity", id, user_id) do
    case Devices.get_activity(id, user_id) do
      %{state: "own"} = activity -> activity
      _other -> nil
    end
  end

  defp owned(_kind, _id, _user_id), do: {:error, :unknown_kind}

  defp found({:error, _reason} = error), do: error
  defp found(nil), do: {:error, :not_found}
  defp found(entry), do: {:ok, entry}
end
