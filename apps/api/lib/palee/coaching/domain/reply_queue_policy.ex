defmodule Palee.Coaching.Domain.ReplyQueuePolicy do
  @moduledoc """
  The coach's promised reply time (ADR-098): a client message is due
  `response_sla_hours` after it was sent; without a promise it has no due time.
  """

  def due_at(_sent_at, hours) when hours in [nil, 0], do: nil

  def due_at(%DateTime{} = sent_at, hours) when is_integer(hours),
    do: DateTime.add(sent_at, hours * 3600)

  def overdue?(%{due_at: nil}, _now), do: false
  def overdue?(%{due_at: due_at}, %DateTime{} = now), do: DateTime.compare(now, due_at) == :gt

  @doc "Overdue items first, then by due time, then oldest message."
  def order(items) do
    Enum.sort_by(items, fn item ->
      {if(item.due_at, do: 0, else: 1), item.due_at && DateTime.to_unix(item.due_at),
       DateTime.to_unix(item.sent_at)}
    end)
  end
end
