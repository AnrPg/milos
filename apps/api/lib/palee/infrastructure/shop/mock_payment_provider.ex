defmodule Palee.Infrastructure.Shop.MockPaymentProvider do
  @moduledoc """
  The payment provider until Palee has a card vendor (ADR-190).

  `mode` (application env of this module):

    * `:unavailable` (production default): `availability/1` answers
      `available: false, reason: :no_provider`, so the basket greys out
      «Πληρωμή», and `capture/2` refuses with `:online_payment_unavailable`.
    * `:simulate` (dev and test): captures succeed, except a
      `payment_token` of `"tok_declined"` (`:card_declined`) or
      `"tok_error"` (`:provider_error`). A retried capture with the same
      idempotency key returns the same reference.
  """

  @behaviour Palee.Shop.Ports.PaymentProvider

  @provider "mock"

  @impl true
  def availability(_context) do
    case mode() do
      :simulate -> %{available: true, reason: nil, provider: @provider}
      _unavailable -> %{available: false, reason: :no_provider, provider: @provider}
    end
  end

  # Desk methods are recorded by staff (the terminal is not integrated), so
  # they are always on offer; the online card follows `availability/1`.
  @impl true
  def payment_methods(context) do
    online = availability(context)

    Enum.map(Palee.Shop.Domain.OrderLifecycle.desk_methods(), fn method ->
      %{method: method, channel: :pos, available: true, reason: nil, provider: nil}
    end) ++
      [
        %{
          method: :card_online,
          channel: :online,
          available: online.available,
          reason: online.reason,
          provider: online.provider
        }
      ]
  end

  @impl true
  def capture(_context, %{idempotency_key: key} = charge) when is_binary(key) do
    case {mode(), Map.get(charge, :payment_token)} do
      {:simulate, "tok_declined"} ->
        {:error, :card_declined}

      {:simulate, "tok_error"} ->
        {:error, :provider_error}

      {:simulate, _token} ->
        {:ok, %{provider: @provider, reference: reference(key), captured_at: DateTime.utc_now()}}

      _unavailable ->
        {:error, :online_payment_unavailable}
    end
  end

  def capture(_context, _charge), do: {:error, :idempotency_key_required}

  @impl true
  def refund(_context, %{reference: reference, idempotency_key: key}) when is_binary(reference) do
    case mode() do
      :simulate -> {:ok, %{reference: reference("refund:" <> key)}}
      _unavailable -> {:error, :online_payment_unavailable}
    end
  end

  def refund(_context, _refund), do: {:error, :invalid_refund}

  defp reference(key),
    do:
      "mock_" <>
        (:crypto.hash(:sha256, key) |> Base.url_encode64(padding: false) |> binary_part(0, 20))

  defp mode do
    :palee |> Application.get_env(__MODULE__, []) |> Keyword.get(:mode, :unavailable)
  end
end
