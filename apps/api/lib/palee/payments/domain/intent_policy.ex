defmodule Palee.Payments.Domain.IntentPolicy do
  @moduledoc """
  Pure rules of an online payment's life (ADR-246/247).

      payer checkout:    awaiting_payer ─► succeeded | failed | cancelled | expired
      saved-card charge: scheduled ─► processing? ─► succeeded | failed
                                   └─ declined: scheduled again (1, 3, 7 days)

  A payer checkout is settled when the provider tells us (webhook, return
  page) and, in case both are lost, by polling until it expires. A charge
  of a saved card is retried after a decline on the dunning schedule and
  after a provider outage on a short backoff. Every state comes from what
  the provider reports when asked, never from a webhook body.
  """

  @purposes ~w(finance_invoice membership_package shop_order booking)
  @currencies ~w(EUR GBP USD CHF)
  @open ~w(scheduled awaiting_payer processing)
  @max_amount_cents 10_000_000
  @checkout_ttl_seconds 3_600
  # Polling a payer checkout when no webhook came (seconds after the last look).
  @poll [120, 300, 900, 1_800, 3_600]
  # Dunning after a declined saved-card charge: days after the first try.
  @dunning_days [1, 3, 7]
  # A provider outage: minutes before trying a saved-card charge again.
  @outage_minutes [5, 30, 120, 360]
  @fulfilment_backoff [60, 300, 1_800, 3_600, 21_600]
  @max_fulfilment_attempts 12
  @lease_seconds 300

  def purposes, do: @purposes
  def currencies, do: @currencies
  def open_statuses, do: @open
  def checkout_ttl_seconds, do: @checkout_ttl_seconds
  def lease_seconds, do: @lease_seconds
  def dunning_days, do: @dunning_days
  def max_fulfilment_attempts, do: @max_fulfilment_attempts

  @doc "Checks the money and purpose of a new intent."
  def validate_new(request) do
    cond do
      request[:purpose_type] not in @purposes ->
        {:error, :invalid_payment_purpose}

      not is_binary(request[:purpose_id]) ->
        {:error, :invalid_payment_purpose}

      not (is_integer(request[:amount_cents]) and request[:amount_cents] > 0 and
               request[:amount_cents] <= @max_amount_cents) ->
        {:error, :invalid_payment_amount}

      request[:currency] not in @currencies ->
        {:error, :unsupported_currency}

      not (is_binary(request[:idempotency_key]) and
               byte_size(request[:idempotency_key]) in 8..200) ->
        {:error, :idempotency_key_required}

      true ->
        :ok
    end
  end

  @doc "A short text the provider shows the payer and prints on statements."
  def description(text) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x1F\x7F]/u, " ")
    |> String.trim()
    |> String.slice(0, 120)
    |> case do
      "" -> "Payment"
      clean -> clean
    end
  end

  def description(_text), do: "Payment"

  def open?(%{status: status}), do: status in @open

  @doc """
  The changes after asking the provider about a payer checkout.
  `result` is the gateway's normalized answer.
  """
  def checkout_outcome(intent, {:ok, %{status: :succeeded} = payment}, now),
    do: succeeded(intent, payment, now)

  def checkout_outcome(_intent, {:ok, %{status: status} = payment}, _now)
      when status in [:failed, :cancelled] do
    failure = failure(payment)

    %{
      status: if(status == :failed, do: "failed", else: "cancelled"),
      next_attempt_at: nil,
      provider_transaction_id: payment[:transaction_id],
      failure_code: truncate(failure[:code], 100),
      failure_message: truncate(failure[:message], 500),
      claimed_at: nil
    }
  end

  def checkout_outcome(intent, result, now) do
    # Still waiting (or the provider did not answer): look again later,
    # until the checkout has expired.
    if expired?(intent, now) and match?({:ok, _payment}, result) do
      %{status: "expired", next_attempt_at: nil, claimed_at: nil, failure_code: "expired"}
    else
      %{
        next_attempt_at: next_poll(intent, now),
        claimed_at: nil,
        attempts: (intent.attempts || 0) + 1
      }
      |> Map.merge(error_fields(result))
    end
  end

  defp expired?(%{expires_at: nil}, _now), do: false
  defp expired?(%{expires_at: at}, now), do: DateTime.compare(now, at) != :lt

  defp next_poll(intent, now) do
    delay = Enum.at(@poll, min(intent.attempts || 0, length(@poll) - 1))
    candidate = DateTime.add(now, delay, :second)

    case intent.expires_at do
      nil ->
        candidate

      expires ->
        # One last look just after expiry decides the outcome.
        last = DateTime.add(expires, 60, :second)
        if DateTime.compare(candidate, last) == :gt, do: last, else: candidate
    end
  end

  @doc "The changes after charging a saved card."
  def charge_outcome(intent, {:ok, %{status: :succeeded} = payment}, now),
    do: succeeded(intent, payment, now)

  def charge_outcome(intent, {:ok, %{status: :pending} = payment}, now) do
    %{
      status: "processing",
      provider_transaction_id: payment[:transaction_id],
      next_attempt_at: DateTime.add(now, 300, :second),
      claimed_at: nil,
      attempts: intent.attempts + 1
    }
  end

  def charge_outcome(intent, {:ok, %{status: status} = payment}, now)
      when status in [:failed, :cancelled],
      do: declined(intent, failure(payment), now)

  def charge_outcome(intent, {:error, {:declined, code, message}}, now),
    do: declined(intent, %{code: code, message: message}, now)

  # Refused credentials or request, or a request that may have reached the
  # provider without an idempotency key: never retried by itself.
  def charge_outcome(intent, {:error, {kind, _detail}} = result, _now)
      when kind in [:unauthorized, :invalid, :uncertain] do
    %{status: "failed", next_attempt_at: nil, claimed_at: nil, attempts: intent.attempts + 1}
    |> Map.merge(error_fields(result))
  end

  def charge_outcome(intent, result, now) do
    case Enum.at(@outage_minutes, intent.attempts) do
      nil ->
        %{status: "failed", next_attempt_at: nil, claimed_at: nil, attempts: intent.attempts + 1}
        |> Map.merge(error_fields(result))

      delay ->
        %{
          status: "scheduled",
          next_attempt_at: DateTime.add(now, delay * 60, :second),
          claimed_at: nil,
          attempts: intent.attempts + 1
        }
        |> Map.merge(error_fields(result))
    end
  end

  defp declined(intent, failure, now) do
    declines = Map.get(intent.consent || %{}, "declines", 0) + 1
    started = intent.inserted_at || now

    base = %{
      claimed_at: nil,
      attempts: intent.attempts + 1,
      failure_code: truncate(failure[:code], 100),
      failure_message: truncate(failure[:message], 500)
    }

    case Enum.at(@dunning_days, declines - 1) do
      days when is_integer(days) and not is_nil(intent.payment_method_id) ->
        Map.merge(base, %{
          status: "scheduled",
          next_attempt_at: DateTime.add(started, days * 86_400, :second),
          consent: Map.put(intent.consent || %{}, "declines", declines)
        })

      _no_more ->
        Map.merge(base, %{status: "failed", next_attempt_at: nil})
    end
  end

  defp succeeded(intent, payment, now) do
    card = payment[:card] || %{}

    %{
      status: "succeeded",
      provider_transaction_id: payment[:transaction_id],
      succeeded_at: now,
      next_attempt_at: nil,
      claimed_at: nil,
      failure_code: nil,
      failure_message: nil,
      card_brand: truncate(card[:brand], 30),
      card_last4: last4(card[:last4]),
      fulfilment_status: "pending",
      attempts: (intent.attempts || 0) + 1
    }
  end

  @doc "Whether a provider reported an amount or currency different from the intent."
  def amount_mismatch?(intent, %{amount_cents: cents, currency: currency})
      when is_integer(cents) and is_binary(currency),
      do: cents != intent.amount_cents or String.upcase(currency) != intent.currency

  def amount_mismatch?(intent, %{amount_cents: cents}) when is_integer(cents),
    do: cents != intent.amount_cents

  def amount_mismatch?(_intent, _payment), do: false

  @doc "The fulfilment changes after one try."
  def fulfilment_outcome(_intent, {:ok, result}, now) do
    %{
      fulfilment_status: "done",
      fulfilled_at: now,
      fulfilment_error: nil,
      finance_payment_id: result[:finance_payment_id],
      fiscal_document_id: result[:fiscal_document_id],
      claimed_at: nil
    }
    # ADR-272: a Tap to Pay tip's attribution is written with the fulfilment.
    |> Map.merge(Map.take(result, [:tip_attribution, :tip_recipient_user_id, :tip_recipient_role]))
  end

  def fulfilment_outcome(intent, {:error, reason}, now) do
    attempts = intent.fulfilment_attempts + 1
    delay = Enum.at(@fulfilment_backoff, attempts - 1, List.last(@fulfilment_backoff))

    %{
      fulfilment_attempts: attempts,
      fulfilment_error: reason |> inspect() |> truncate(500),
      fulfilment_status: if(attempts >= @max_fulfilment_attempts, do: "failed", else: "pending"),
      next_attempt_at: DateTime.add(now, delay, :second),
      claimed_at: nil
    }
  end

  @doc "Checks a refund request against what is left of the payment."
  def validate_refund(intent, amount_cents) do
    left = intent.amount_cents - intent.refunded_cents

    cond do
      intent.status != "succeeded" -> {:error, :payment_not_refundable}
      not (is_integer(amount_cents) and amount_cents > 0) -> {:error, :invalid_refund_amount}
      amount_cents > left -> {:error, :refund_exceeds_payment}
      true -> :ok
    end
  end

  defp failure(payment), do: payment[:failure] || %{}

  defp error_fields({:error, reason}) do
    {code, message} =
      case reason do
        {:declined, code, message} -> {code, message}
        {kind, detail} when is_atom(kind) -> {Atom.to_string(kind), inspect(detail)}
        other -> {"error", inspect(other)}
      end

    %{failure_code: truncate(to_string(code), 100), failure_message: truncate(message, 500)}
  end

  defp error_fields(_ok), do: %{}

  defp last4(value) when is_binary(value) do
    if value =~ ~r/^\d{4}$/, do: value, else: nil
  end

  defp last4(_value), do: nil

  defp truncate(nil, _max), do: nil
  defp truncate(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp truncate(value, max), do: value |> to_string() |> String.slice(0, max)
end
