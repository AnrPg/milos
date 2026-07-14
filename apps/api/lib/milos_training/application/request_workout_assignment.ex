defmodule MilosTraining.Application.RequestWorkoutAssignment do
  alias MilosTraining.{Identity, Messaging}

  def call(%{role: :athlete} = athlete, params) when is_map(params) do
    with {:ok, requested_for} <-
           parse_requested_for(params["requested_for"] || params[:requested_for]),
         :ok <- reject_past_date(requested_for),
         admins when admins != [] <- Identity.list_by_role(:admin),
         {:ok, sent_count} <- notify_admins(athlete, requested_for, params, admins) do
      {:ok, %{requested_for: requested_for, notified_admins: sent_count}}
    else
      [] -> {:error, :no_admins}
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_user, _params), do: {:error, :forbidden}

  defp parse_requested_for(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :bad_request}
    end
  end

  defp parse_requested_for(%Date{} = date), do: {:ok, date}
  defp parse_requested_for(_value), do: {:error, :bad_request}

  defp reject_past_date(date) do
    if Date.compare(date, Date.utc_today()) == :lt do
      {:error, :past_date}
    else
      :ok
    end
  end

  defp notify_admins(athlete, requested_for, params, admins) do
    note = params["note"] || params[:note]
    body = request_body(athlete, requested_for, note)

    results =
      Enum.map(admins, fn admin ->
        with {:ok, thread} <-
               Messaging.get_or_create_thread(%{
                 context_type: :direct,
                 actor_id: athlete.id,
                 participant_id: admin.id
               }),
             {:ok, _message} <-
               Messaging.send_message(%{
                 thread_id: thread.id,
                 sender_id: athlete.id,
                 body: body,
                 message_type: :chat
               }) do
          :ok
        end
      end)

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil -> {:ok, length(results)}
      error -> error
    end
  end

  defp request_body(athlete, requested_for, note) do
    base =
      "#{athlete.nickname} requested a workout assignment for #{Date.to_iso8601(requested_for)}."

    case normalize_note(note) do
      nil -> base
      note -> "#{base}\n\nNote: #{note}"
    end
  end

  defp normalize_note(note) when is_binary(note) do
    note
    |> String.trim()
    |> case do
      "" -> nil
      value -> String.slice(value, 0, 500)
    end
  end

  defp normalize_note(_note), do: nil
end
