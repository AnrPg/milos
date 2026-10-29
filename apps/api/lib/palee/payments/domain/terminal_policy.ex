defmodule Palee.Payments.Domain.TerminalPolicy do
  @moduledoc """
  Pure rules of a card tapped at the desk through the provider's terminal
  app (ADR-249). A terminal payment is a payment intent with
  `initiation: "terminal"`:

      awaiting_payer ─► succeeded | failed | cancelled | expired
           │  device result with a transaction: confirmed with the provider
           │  device failure/cancel without one: closed at once
           └─ no result: looked up by reference after the request expired

  Money is recorded only from what the provider says when asked, never from
  the phone. A result the provider cannot confirm yet stays open
  (`terminal_unconfirmed`), is asked about again on a schedule, and then
  waits for staff.

  ADR-264: the provider's amount may be more than the request by a tip
  and a card surcharge it names; the rest must be the requested amount
  exactly (`split/2`). A walk-in may pay a shop order or a free sale.
  """

  alias Palee.Payments.Domain.IntentPolicy

  @purposes ~w(finance_invoice membership_package shop_order free_sale)
  # Purposes a walk-in (no member) may pay at the terminal (ADR-264).
  @walk_in_purposes ~w(shop_order free_sale)
  @request_ttl_seconds 900
  # Asking the provider again about an unconfirmed result, or looking for a
  # lost one (seconds after the previous look).
  @poll [30, 120, 300, 900, 3_600, 21_600]
  # A transaction created this long before the request is not its payment.
  @clock_skew_seconds 300
  @reference_version "pt1"

  def purposes, do: @purposes
  def walk_in_purposes, do: @walk_in_purposes
  def request_ttl_seconds, do: @request_ttl_seconds
  def poll_schedule, do: @poll

  @doc "Checks the money, purpose and payer of a new terminal payment."
  def validate_new(request) do
    with :ok <- IntentPolicy.validate_new(Map.put(request, :purpose_type, "finance_invoice")) do
      cond do
        request[:purpose_type] not in @purposes ->
          {:error, :invalid_payment_purpose}

        is_nil(request[:user_id]) and request[:purpose_type] not in @walk_in_purposes ->
          {:error, :terminal_member_required}

        true ->
          :ok
      end
    end
  end

  # ── Reference ───────────────────────────────────────────────────────────

  @doc """
  The reference the terminal app keeps with the transaction
  (`clientTransactionId` → Viva's merchant reference): the intent id and
  a signature over the business, intent, amount and currency.
  """
  def reference(intent, key) when is_binary(key) do
    Enum.join([@reference_version, intent.id, signature(intent, key)], ".")
  end

  @doc "The intent id a reference names (not yet verified)."
  def reference_intent_id(reference) when is_binary(reference) do
    with [@reference_version, id, _signature] <- String.split(reference, ".", parts: 3),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, id}
    else
      _invalid -> :error
    end
  end

  def reference_intent_id(_reference), do: :error

  @doc "Whether `reference` was made by Palee for exactly this intent."
  def valid_reference?(reference, intent, key) when is_binary(reference) do
    Plug.Crypto.secure_compare(reference, reference(intent, key))
  end

  def valid_reference?(_reference, _intent, _key), do: false

  defp signature(intent, key) do
    payload =
      Enum.join(
        [intent.organization_id, intent.id, intent.amount_cents, intent.currency],
        ":"
      )

    :hmac
    |> :crypto.mac(:sha256, key, payload)
    |> binary_part(0, 16)
    |> Base.url_encode64(padding: false)
  end

  @doc "Whether the phone may still hand the request to the terminal app."
  def launchable?(%{status: "awaiting_payer", provider_transaction_id: nil} = intent, now),
    do: DateTime.compare(now, intent.expires_at) == :lt

  def launchable?(_intent, _now), do: false

  # ── Device result ───────────────────────────────────────────────────────

  @doc """
  Normalizes what the terminal app returned through the phone:
  `status` (`success`, `fail`, `cancelled`, anything else is an error),
  `transaction_id`, `message`.
  """
  def device_result(params) do
    %{
      status:
        case text(params[:status], 20) do
          "success" -> :success
          "fail" -> :fail
          status when status in ["cancel", "cancelled", "canceled"] -> :cancelled
          _other -> :error
        end,
      transaction_id: text(params[:transaction_id], 200),
      message: text(params[:message], 500)
    }
  end

  @doc """
  What a device result does to the intent:

    * `{:confirm, changes}` – ask the provider about the transaction now;
    * `{:close, changes}` – no transaction: nothing was paid;
    * `:unchanged` – a duplicate callback, or a late failure after a
      transaction is known;
    * `{:error, :terminal_request_used}` – another transaction for a
      request that already has one.
  """
  def apply_device(intent, %{transaction_id: transaction_id} = device, now)
      when is_binary(transaction_id) do
    cond do
      intent.provider_transaction_id == transaction_id ->
        :unchanged

      is_binary(intent.provider_transaction_id) ->
        {:error, :terminal_request_used}

      intent.status == "succeeded" ->
        {:error, :terminal_request_used}

      true ->
        # A transaction after the phone reported a failure, a cancel or
        # nothing at all: whatever the provider took is recorded.
        {:confirm,
         %{
           status: "awaiting_payer",
           provider_transaction_id: transaction_id,
           next_attempt_at: now,
           claimed_at: nil,
           attempts: 0,
           failure_code: nil,
           failure_message: device.message
         }}
    end
  end

  def apply_device(%{status: "awaiting_payer", provider_transaction_id: nil}, device, _now) do
    {code, status} =
      case device.status do
        :cancelled -> {"terminal_cancelled", "cancelled"}
        :fail -> {"terminal_declined", "failed"}
        # The phone says paid but gives no transaction: nothing to confirm.
        :success -> {"terminal_no_transaction", "failed"}
        :error -> {"terminal_app_error", "failed"}
      end

    {:close,
     %{
       status: status,
       next_attempt_at: nil,
       claimed_at: nil,
       failure_code: code,
       failure_message: device.message
     }}
  end

  def apply_device(_intent, _device, _now), do: :unchanged

  # ── Provider ────────────────────────────────────────────────────────────

  @doc """
  The changes after asking the provider about the intent's transaction.
  `reference` is the one Palee gave the request.
  """
  def confirm_outcome(intent, {:ok, %{status: :succeeded} = transaction}, reference, now) do
    case mismatch(intent, transaction, reference) do
      {:ok, extras} ->
        card = transaction[:card] || %{}
        id = transaction[:transaction_id] || intent.provider_transaction_id

        %{
          status: "succeeded",
          tip_cents: extras.tip_cents,
          surcharge_cents: extras.surcharge_cents,
          provider_ref: id,
          provider_transaction_id: id,
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

      {:error, code} ->
        # Never paid in Palee's books; staff see why.
        %{
          status: "failed",
          next_attempt_at: nil,
          claimed_at: nil,
          failure_code: code,
          failure_message: "provider transaction #{intent.provider_transaction_id}",
          attempts: (intent.attempts || 0) + 1
        }
    end
  end

  def confirm_outcome(intent, {:ok, %{status: status} = transaction}, _reference, _now)
      when status in [:failed, :cancelled] do
    failure = transaction[:failure] || %{}

    %{
      status: if(status == :failed, do: "failed", else: "cancelled"),
      next_attempt_at: nil,
      claimed_at: nil,
      failure_code: truncate(failure[:code] || "terminal_#{status}", 100),
      failure_message: truncate(failure[:message], 500),
      attempts: (intent.attempts || 0) + 1
    }
  end

  # Pending at the provider, unknown to it yet, or the provider did not
  # answer: still open, asked again later, then left for staff.
  def confirm_outcome(intent, result, _reference, now) do
    %{
      status: "awaiting_payer",
      next_attempt_at: next_poll(intent, now),
      claimed_at: nil,
      failure_code: "terminal_unconfirmed",
      failure_message: unconfirmed_message(result),
      attempts: (intent.attempts || 0) + 1
    }
  end

  @doc """
  When the provider's lookup by reference found nothing (or could not be
  asked): look again on the schedule, then the request has expired.
  """
  def lost_outcome(intent, result, now) do
    case next_poll(intent, now) do
      nil ->
        %{
          status: "expired",
          next_attempt_at: nil,
          claimed_at: nil,
          failure_code: "terminal_no_result",
          failure_message: unconfirmed_message(result),
          attempts: (intent.attempts || 0) + 1
        }

      at ->
        %{
          next_attempt_at: at,
          claimed_at: nil,
          failure_message: unconfirmed_message(result),
          attempts: (intent.attempts || 0) + 1
        }
    end
  end

  @doc "When to look for a lost result first: just after the request expired."
  def first_lookup_at(intent), do: DateTime.add(intent.expires_at, 60, :second)

  @doc "Whether it is too early to look for a result that never came."
  def too_early_to_look?(intent, now),
    do: DateTime.compare(now, first_lookup_at(intent)) == :lt

  defp next_poll(intent, now) do
    case Enum.at(@poll, intent.attempts || 0) do
      nil -> nil
      delay -> DateTime.add(now, delay, :second)
    end
  end

  defp mismatch(intent, transaction, reference) do
    cond do
      is_binary(transaction[:reference]) and transaction[:reference] != "" and
          transaction[:reference] != reference ->
        {:error, "reference_mismatch"}

      too_old?(intent, transaction[:created_at]) ->
        {:error, "transaction_before_request"}

      true ->
        split(intent, transaction)
    end
  end

  @doc """
  ADR-264: splits the amount the provider confirmed into the requested
  amount, a tip and a card surcharge. The provider's amount is everything
  the card paid; `tip_cents` and `surcharge_cents` are the parts of it it
  names. What is left must be the intent's amount in its currency, else
  `{:error, "amount_mismatch"}` (an unknown extra is never accepted).
  """
  def split(intent, transaction) do
    tip = transaction[:tip_cents] || 0
    surcharge = transaction[:surcharge_cents] || 0
    amount = transaction[:amount_cents]
    currency = transaction[:currency]

    cond do
      not (is_integer(tip) and tip >= 0 and is_integer(surcharge) and surcharge >= 0) ->
        {:error, "amount_mismatch"}

      is_binary(currency) and String.upcase(currency) != intent.currency ->
        {:error, "amount_mismatch"}

      is_integer(amount) and amount - tip - surcharge != intent.amount_cents ->
        {:error, "amount_mismatch"}

      true ->
        {:ok, %{tip_cents: tip, surcharge_cents: surcharge}}
    end
  end

  defp too_old?(%{inserted_at: %DateTime{} = requested}, %DateTime{} = created),
    do: DateTime.diff(requested, created, :second) > @clock_skew_seconds

  defp too_old?(_intent, _created), do: false

  defp unconfirmed_message({:ok, %{status: :pending}}), do: "pending at the provider"
  defp unconfirmed_message({:ok, nil}), do: "no transaction with this reference yet"

  defp unconfirmed_message({:error, reason}),
    do: reason |> inspect() |> truncate(500)

  defp unconfirmed_message(_result), do: nil

  defp text(value, max) when is_binary(value) do
    case value |> String.replace(~r/[\x00-\x1F\x7F]/u, " ") |> String.trim() do
      "" -> nil
      clean -> String.slice(clean, 0, max)
    end
  end

  defp text(value, max) when is_integer(value), do: value |> Integer.to_string() |> text(max)
  defp text(_value, _max), do: nil

  defp last4(value) when is_binary(value) do
    if value =~ ~r/^\d{4}$/, do: value, else: nil
  end

  defp last4(_value), do: nil

  defp truncate(nil, _max), do: nil
  defp truncate(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp truncate(value, max), do: value |> to_string() |> String.slice(0, max)
end
