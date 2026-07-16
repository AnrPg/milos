defmodule MilosTraining.Application.SendMessage do
  @moduledoc """
  Cross-context orchestration for metered coaching notes.

  Ordinary chat remains entirely inside Messaging. An admin-authored coaching
  note reserves one touchpoint for each non-admin recipient, then finalizes the
  reservations after Messaging durably creates the message.
  """

  alias MilosTraining.{Finance, Identity, Messaging}

  def call(%{id: sender_id, role: :admin}, %{message_type: :coaching_note} = params) do
    delivery_id = Ecto.UUID.generate()

    with {:ok, thread} <- Messaging.get_thread(params.thread_id, sender_id),
         recipients <- coaching_recipients(thread, sender_id),
         {:ok, reservations} <- reserve_touchpoints(recipients, delivery_id),
         {:ok, message} <- send_or_release(params, reservations, delivery_id) do
      {:ok, message}
    end
  end

  def call(_sender, params), do: Messaging.send_message(params, %{reservations: []})

  defp coaching_recipients(thread, sender_id) do
    ids =
      thread.participants
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&(&1 == sender_id))

    ids
    |> Identity.list_by_ids()
    |> Enum.filter(&(&1.role in [:member, :athlete]))
  end

  defp reserve_touchpoints(recipients, delivery_id) do
    Enum.reduce_while(recipients, {:ok, []}, fn recipient, {:ok, reservations} ->
      case Finance.reserve_entitlement(recipient.id, %{
             channel: :coach_messaging,
             capability: :receive_coaching_touchpoints,
             allowance: :coaching_touchpoints,
             quantity: 1,
             occurred_on: Date.utc_today(),
             source_context: "messaging",
             source_id: delivery_id,
             idempotency_key: "coach-check-in:#{delivery_id}:#{recipient.id}",
             metadata: %{"kind" => "coach_check_in"}
           }) do
        {:ok, reservation} ->
          {:cont, {:ok, [{recipient.id, reservation} | reservations]}}

        error ->
          release(reservations, "Coaching-note entitlement reservation failed")
          {:halt, error}
      end
    end)
  end

  defp send_or_release(params, reservations, delivery_id) do
    delivery = %{
      reservations:
        Enum.flat_map(reservations, fn
          {_recipient_id, %{id: nil}} ->
            []

          {recipient_id, %{id: reservation_id}} ->
            [
              %{
                recipient_id: recipient_id,
                reservation_id: reservation_id,
                delivery_id: delivery_id
              }
            ]
        end)
    }

    case Messaging.send_message(params, delivery) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        release(reservations, "Coaching note was not created")
        {:error, reason}
    end
  end

  defp release(reservations, reason) do
    Enum.each(reservations, fn
      {_recipient_id, %{id: nil}} ->
        :ok

      {_recipient_id, %{id: reservation_id}} ->
        Finance.release_entitlement(reservation_id, %{
          reason: reason,
          idempotency_key: "coach-check-in-release:#{reservation_id}"
        })
    end)

    :ok
  end
end
