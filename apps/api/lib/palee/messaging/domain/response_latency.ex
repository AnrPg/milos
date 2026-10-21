defmodule Palee.Messaging.Domain.ResponseLatency do
  @moduledoc """
  Pure staff-response facts for messaging analytics (ADR-123).

  A staff message is a *first staff response* when the closest preceding
  non-system message in the thread came from a non-staff participant. Its
  latency is measured from the earliest message of that unanswered member run
  (the oldest member message since the previous staff message), so a member
  who sends three messages before anyone answers is measured from the first.
  """

  @doc """
  `messages` are the thread's recent messages (any order, may include
  `new_message`); `staff_ids` are the organization's staff user ids.
  Returns `nil` or `%{response_latency_seconds:, pending_member_message_count:}`.
  """
  def first_staff_response(messages, new_message, staff_ids) when is_list(messages) do
    staff = MapSet.new(staff_ids)

    if MapSet.member?(staff, field(new_message, :sender_id)) do
      messages
      |> Enum.reject(&(field(&1, :id) == field(new_message, :id)))
      |> Enum.reject(&(to_string(field(&1, :message_type)) == "system"))
      |> Enum.filter(&before?(&1, new_message))
      |> Enum.sort_by(&order_key/1, :desc)
      |> Enum.take_while(&(not MapSet.member?(staff, field(&1, :sender_id))))
      |> facts(new_message)
    end
  end

  defp facts([], _new_message), do: nil

  defp facts(pending, new_message) do
    earliest = List.last(pending)

    %{
      response_latency_seconds:
        max(diff_seconds(field(new_message, :inserted_at), field(earliest, :inserted_at)), 0),
      pending_member_message_count: length(pending)
    }
  end

  defp before?(message, new_message) do
    case {field(message, :sequence_number), field(new_message, :sequence_number)} do
      {a, b} when is_integer(a) and is_integer(b) -> a < b
      _other -> compare(field(message, :inserted_at), field(new_message, :inserted_at)) == :lt
    end
  end

  defp order_key(message),
    do: {field(message, :sequence_number) || 0, to_sortable(field(message, :inserted_at))}

  defp to_sortable(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)

  defp to_sortable(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

  defp to_sortable(_other), do: 0

  defp compare(a, b), do: if(to_sortable(a) < to_sortable(b), do: :lt, else: :gt)

  defp diff_seconds(later, earlier), do: div(to_sortable(later) - to_sortable(earlier), 1_000_000)

  defp field(map, key) when is_map(map), do: Map.get(map, key)
  defp field(_map, _key), do: nil
end
