defmodule Palee.Email.Commands.HandleProviderEvents do
  @moduledoc """
  `Palee.Email.handle_provider_events/2` (ADR-212): applies the events of
  one provider webhook body (`ProviderEvent.parse_brevo/1`).

  Each event is matched to its outbox message by Message-ID, else to the
  newest message sent to its address in the last 30 days. Then, unless the
  same event was already applied (its digest is recorded):

    * a hard bounce, an invalid address or a block suppresses the address
      (`bounce`) and marks the message `bounced`; a complaint suppresses it
      (`complaint`) and marks the message `complained`;
    * an unsubscribe opts the address out of that message's kind, when it
      is transactional mail (security and account mail ignore opt-outs);
    * a delivery sets the message's `delivered_at`;
    * a soft bounce (and the provider's own deferrals and errors) is only
      recorded: the provider retries it.

  Every action is idempotent by itself; the digest check keeps a retried
  webhook from re-suppressing an address a vendor has since taken off the
  list. Nothing here logs an address.
  """

  alias Palee.Email.Domain.{Address, ProviderEvent}
  alias Palee.Email.Message

  @match_window_days 30

  @spec call(:brevo, term(), DateTime.t()) ::
          {:ok,
           %{
             applied: non_neg_integer(),
             duplicate: non_neg_integer(),
             unmatched: non_neg_integer()
           }}
          | {:error, :invalid_payload}
  def call(:brevo, payload, %DateTime{} = now) do
    with {:ok, events} <- ProviderEvent.parse_brevo(payload) do
      store = Palee.Email.message_store()

      results = Enum.map(events, &handle(store, &1, now))

      {:ok,
       Enum.reduce(results, %{applied: 0, duplicate: 0, unmatched: 0}, fn result, totals ->
         Map.update!(totals, result, &(&1 + 1))
       end)}
    end
  end

  defp handle(store, event, now) do
    message = match(store, event, now)
    address = event.address || (message && message.to_address)

    result =
      cond do
        is_nil(address) -> :unmatched
        store.event_recorded?(event.digest) -> :duplicate
        true -> apply_event(store, event, address, message, now)
      end

    :telemetry.execute([:palee, :email, :provider_event], %{count: 1}, %{
      provider: "brevo",
      event: event.event,
      result: result
    })

    result
  end

  defp match(store, %{message_id: message_id} = event, now) when is_binary(message_id) do
    store.get_by_message_id(message_id) || match(store, %{event | message_id: nil}, now)
  end

  defp match(store, %{address: address}, now) when is_binary(address),
    do: store.latest_sent_to(address, DateTime.add(now, -@match_window_days, :day))

  defp match(_store, _event, _now), do: nil

  defp apply_event(store, event, address, message, now) do
    digest = Address.digest(address)

    case ProviderEvent.action(event) do
      {:suppress, reason, status} ->
        {:ok, _suppression} = store.suppress(digest, Atom.to_string(reason))

        mark(
          store,
          message,
          %{status: status},
          if(reason == :bounce, do: :bounced, else: :complained)
        )

      :opt_out ->
        if match?(%Message{category: "transactional"}, message),
          do: store.opt_out(digest, message.kind)

      :delivered ->
        if match?(%Message{delivered_at: nil}, message),
          do: mark(store, message, %{delivered_at: event.occurred_at || now}, :delivered)

      :record ->
        :ok
    end

    {:ok, _recorded} =
      store.record_event(%{
        event_digest: event.digest,
        provider: "brevo",
        event: Atom.to_string(event.event),
        email_message_id: message && message.id,
        address_digest: digest,
        reason: event.reason,
        occurred_at: event.occurred_at
      })

    :applied
  end

  defp mark(_store, nil, _fields, _event), do: :ok

  defp mark(store, %Message{} = message, fields, event) do
    {:ok, message} = store.update(message, fields)
    Palee.Email.emit(event, message)
  end
end
