defmodule Palee.Application.GetMyClientStats do
  @moduledoc """
  Πελάτες μου stats for the signed-in coach (ADR-140 §7): coaching messages
  they sent this week and their clients' threads waiting for an answer.
  """

  alias Palee.{Coaching, Messaging}

  def call(%{user_id: coach_id} = context, now \\ DateTime.utc_now()) do
    client_ids = Coaching.list_client_ids(context, coach_id)

    Messaging.with_tenant_context(context, fn ->
      %{
        client_count: length(client_ids),
        coaching_messages_this_week:
          Messaging.count_sent(coach_id, :coaching_message, week_start(now)),
        awaiting_reply: Messaging.count_awaiting_reply(coach_id, client_ids)
      }
    end)
  end

  defp week_start(now) do
    date = DateTime.to_date(now)

    date
    |> Date.add(1 - Date.day_of_week(date))
    |> NaiveDateTime.new!(~T[00:00:00])
  end
end
