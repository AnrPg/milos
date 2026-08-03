defmodule MilosTraining.Notifications.Domain.NotificationDedupe do
  def booking_key(user_id, type, booking_id)
      when is_binary(user_id) and is_binary(booking_id) and is_atom(type) do
    Enum.join(["booking", user_id, Atom.to_string(type), booking_id], ":")
  end

  def booking_key(_user_id, _type, _booking_id), do: nil

  def batch_key(user_id, type, occurred_at)
      when is_binary(user_id) and is_atom(type) do
    with {:ok, datetime} <- normalize_datetime(occurred_at) do
      bucket = div(DateTime.to_unix(datetime), 60)
      Enum.join(["batch", user_id, Atom.to_string(type), bucket], ":")
    else
      _ -> nil
    end
  end

  def batch_key(_user_id, _type, _occurred_at), do: nil

  def workout_note_key(user_id, note_id)
      when is_binary(user_id) and is_binary(note_id) do
    Enum.join(["workout_note", user_id, note_id], ":")
  end

  def workout_note_key(_user_id, _note_id), do: nil

  def admin_note_key(user_id, note_id)
      when is_binary(user_id) and is_binary(note_id) do
    Enum.join(["admin_note", user_id, note_id], ":")
  end

  def admin_note_key(_user_id, _note_id), do: nil

  def challenge_completed_key(user_id, challenge_id)
      when is_binary(user_id) and is_binary(challenge_id) do
    Enum.join(["challenge_completed", user_id, challenge_id], ":")
  end

  def challenge_completed_key(_user_id, _challenge_id), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp normalize_datetime(_value), do: :error
end
