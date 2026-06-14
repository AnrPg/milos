defmodule MilosTraining.Messaging.Domain.ThreadPolicy do
  @doc """
  Returns a stable canonical key for a direct thread between two users.
  Sorts the two IDs so the same pair always maps to the same key regardless
  of call order.
  """
  def canonical_pair(user_id_a, user_id_b) do
    [user_id_a, user_id_b]
    |> Enum.sort()
    |> List.to_tuple()
  end

  @doc """
  Returns :ok if `actor` is allowed to send a message in `thread`,
  :error otherwise.
  Actor must be a participant of the thread.
  """
  def can_send?(actor_id, thread) do
    participant_ids = Enum.map(thread.participants, & &1.user_id)

    if actor_id in participant_ids do
      :ok
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Returns :ok if `actor` is allowed to read the thread.
  Same rule as sending — must be a participant.
  """
  def can_read?(actor_id, thread) do
    can_send?(actor_id, thread)
  end
end
