defmodule Palee.Messaging.Domain.BoxInboxPolicy do
  @moduledoc """
  ADR-282: the rules of the box's shared inbox, the thread a box has with
  one person (`context_type: :box`, `context_id` the person).

  Who reads and answers is worked out from the roles at read time, never
  from who happened to be on staff when the thread opened:

    * the person the thread is with;
    * whoever may message for the box (`message_from_box`: owner, admin,
      front desk, accountant), the box's shared inbox;
    * a coach who was brought in (the topic «Προπόνηση», or «Φέρε τον
      coach»), while they still coach at the box.

  Someone who is not a client yet («Νέος») may send a few messages before
  the box answers; clients are never held back.
  """

  @max_unanswered_from_newcomer 3

  @typedoc "What the reader is at the box: in its inbox, and a coach there."
  @type lens :: %{inbox?: boolean(), coach?: boolean()}

  def max_unanswered_from_newcomer, do: @max_unanswered_from_newcomer

  @doc "Whether `user_id` may read and answer `thread`. Other threads keep their own rules."
  @spec may_access?(map(), Ecto.UUID.t(), lens()) :: boolean()
  def may_access?(%{context_type: :box} = thread, user_id, lens) do
    cond do
      thread.context_id == user_id -> true
      lens.inbox? -> true
      lens.coach? -> joined_as(thread, user_id) == :coach
      true -> false
    end
  end

  def may_access?(_thread, _user_id, _lens), do: true

  @doc "Whether a box-side reader writes for the box (the person never does)."
  def writes_for_box?(%{context_type: :box} = thread, user_id, lens),
    do: thread.context_id != user_id and may_access?(thread, user_id, lens)

  def writes_for_box?(_thread, _user_id, _lens), do: false

  @doc "The coaches who were brought into the thread."
  def coach_ids(%{participants: participants}) when is_list(participants),
    do: for(%{joined_as: :coach, user_id: id} <- participants, do: id)

  def coach_ids(_thread), do: []

  @doc """
  Who hears about a new message (Q5 of the mockup): the person's message
  goes to whoever answered last while they still may, else to the whole
  `audience`; a message from the box goes to the person only.
  """
  @spec recipients(map(), Ecto.UUID.t(), Ecto.UUID.t() | nil, [Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def recipients(%{context_id: person_id}, sender_id, handler_id, audience)
      when sender_id == person_id do
    if handler_id && handler_id in audience,
      do: [handler_id],
      else: Enum.uniq(audience) -- [person_id]
  end

  def recipients(%{context_id: person_id}, sender_id, _handler_id, _audience)
      when sender_id != person_id,
      do: [person_id]

  @doc "Whoever answered the person last, from messages newest first."
  def handler(%{context_id: person_id}, messages_newest_first) do
    Enum.find_value(messages_newest_first, fn
      %{sender_id: ^person_id} -> nil
      %{sender_id: sender_id} -> sender_id
    end)
  end

  @doc "How many messages the person sent since the box last answered (newest first)."
  def unanswered(%{context_id: person_id}, messages_newest_first) do
    Enum.take_while(messages_newest_first, &(&1.sender_id == person_id)) |> length()
  end

  @doc "A client always may write; a newcomer only until a few messages wait unanswered."
  def may_write?(:client, _unanswered), do: :ok

  def may_write?(:newcomer, unanswered) when unanswered < @max_unanswered_from_newcomer,
    do: :ok

  def may_write?(:newcomer, _unanswered), do: {:error, :awaiting_box_reply}

  defp joined_as(%{participants: participants}, user_id) when is_list(participants),
    do: Enum.find_value(participants, &(&1.user_id == user_id && &1.joined_as))

  defp joined_as(_thread, _user_id), do: nil
end
