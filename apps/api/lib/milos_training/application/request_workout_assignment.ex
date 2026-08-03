defmodule MilosTraining.Application.RequestWorkoutAssignment do
  alias MilosTraining.{Identity, Notifications}

  def call(%{role: :athlete} = athlete, params) when is_map(params) do
    with {:ok, requested_for} <-
           parse_requested_for(params["requested_for"] || params[:requested_for]),
         :ok <- reject_past_date(requested_for),
         admins when admins != [] <- Identity.list_by_role(:admin),
         :ok <- notify_admins(athlete, requested_for, params) do
      {:ok, %{requested_for: requested_for, notified_admins: length(admins)}}
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

  defp notify_admins(athlete, requested_for, params) do
    note = params["note"] || params[:note]

    Notifications.dispatch_event(:workout_assignment_requested, %{
      request_id: Ecto.UUID.generate(),
      athlete_id: athlete.id,
      athlete_nickname: athlete.nickname,
      requested_for: Date.to_iso8601(requested_for),
      note: normalize_note(note)
    })
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
