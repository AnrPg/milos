defmodule Palee.Shop.Domain.OrderLifecycle do
  @moduledoc """
  How a shop order moves (ADR-190), pure.

  Two independent axes, so "pay at pickup" (the MVP) and "pay online first"
  (later, behind the payment-provider port) both fit:

    * `status` (fulfilment): `placed -> ready_for_pickup -> picked_up`, or
      `cancelled` before pickup.
    * `payment_status` (money): `pending_payment -> paid ->
      partially_refunded -> refunded`, or `void` when an unpaid order is
      cancelled.

  `state/1` folds them into the single vocabulary of the owner's brief:
  `pending_payment`, `paid`, `ready_for_pickup`, `picked_up`, `cancelled`,
  `partially_refunded`, `refunded`.

  A desk (POS) sale is handed over on the spot: it is created `picked_up`
  and is paid in the same transaction.
  """

  @channels [:online, :pos]
  @statuses [:placed, :ready_for_pickup, :picked_up, :cancelled]
  @payment_statuses [:pending_payment, :paid, :partially_refunded, :refunded, :void]
  # How the buyer pays: online modes (chosen at checkout) and desk methods
  # (recorded by staff, the existing Finance manual methods).
  @online_modes [:at_pickup, :on_account, :online]
  @desk_methods [:cash, :card_manual, :bank_transfer, :other]
  @payment_modes @online_modes ++ @desk_methods
  @sources [:direct, :club_post, :promotion_code, :desk, :public_page, :other]
  @default_hold_days 7

  def channels, do: @channels
  def statuses, do: @statuses
  def payment_statuses, do: @payment_statuses
  def payment_modes, do: @payment_modes
  def online_modes, do: @online_modes
  def desk_methods, do: @desk_methods
  def sources, do: @sources
  def default_hold_days, do: @default_hold_days

  @doc "The order's state in the brief's single vocabulary."
  @spec state(map()) :: atom()
  def state(%{status: :cancelled}), do: :cancelled
  def state(%{payment_status: :refunded}), do: :refunded
  def state(%{payment_status: :partially_refunded}), do: :partially_refunded
  def state(%{status: :picked_up}), do: :picked_up
  def state(%{status: :ready_for_pickup}), do: :ready_for_pickup
  def state(%{payment_status: :paid}), do: :paid
  def state(_order), do: :pending_payment

  @doc "Every state value `state/1` can return."
  def states,
    do: [
      :pending_payment,
      :paid,
      :ready_for_pickup,
      :picked_up,
      :cancelled,
      :partially_refunded,
      :refunded
    ]

  @doc "The order attributes after `event`, or why it cannot happen."
  @spec transition(map(), atom(), map()) :: {:ok, map()} | {:error, atom()}
  def transition(order, event, facts \\ %{})

  def transition(%{status: :placed} = order, :mark_ready, facts) do
    if order.payment_status in [:pending_payment, :paid],
      do: {:ok, %{status: :ready_for_pickup, ready_at: facts[:at], handled_by_id: facts[:by]}},
      else: {:error, :invalid_order_transition}
  end

  def transition(%{status: status} = order, :pick_up, facts)
      when status in [:placed, :ready_for_pickup] do
    if order.payment_status == :paid,
      do: {:ok, %{status: :picked_up, picked_up_at: facts[:at], handled_by_id: facts[:by]}},
      else: {:error, :order_not_paid}
  end

  def transition(%{status: status} = order, :cancel, facts)
      when status in [:placed, :ready_for_pickup] do
    if order.payment_status == :pending_payment,
      do:
        {:ok,
         %{
           status: :cancelled,
           payment_status: :void,
           cancelled_at: facts[:at],
           cancel_reason: facts[:reason],
           handled_by_id: facts[:by]
         }},
      else: {:error, :order_paid_refund_first}
  end

  def transition(%{status: status, payment_status: :pending_payment}, :pay, facts)
      when status != :cancelled do
    {:ok, %{payment_status: :paid, paid_at: facts[:at], paid_cents: facts[:amount_cents]}}
  end

  def transition(%{payment_status: payment_status} = order, :refund, facts)
      when payment_status in [:paid, :partially_refunded] do
    amount = facts[:amount_cents]
    refundable = order.paid_cents - order.refunded_cents

    cond do
      not is_integer(amount) or amount <= 0 ->
        {:error, :invalid_refund_amount}

      amount > refundable ->
        {:error, :refund_exceeds_paid}

      true ->
        refunded = order.refunded_cents + amount

        {:ok,
         %{
           refunded_cents: refunded,
           payment_status:
             if(refunded == order.paid_cents, do: :refunded, else: :partially_refunded)
         }}
    end
  end

  def transition(_order, _event, _facts), do: {:error, :invalid_order_transition}

  @doc "Whether an unpaid online order still holds its stock at `now`."
  @spec expired?(map(), DateTime.t()) :: boolean()
  def expired?(
        %{status: status, payment_status: :pending_payment, expires_at: %DateTime{} = at},
        now
      )
      when status in [:placed, :ready_for_pickup],
      do: DateTime.compare(now, at) != :lt

  def expired?(_order, _now), do: false

  @doc "When an online order placed at `now` stops holding its stock."
  @spec expires_at(DateTime.t(), pos_integer()) :: DateTime.t()
  def expires_at(now, hold_days \\ @default_hold_days),
    do: DateTime.add(now, hold_days * 86_400, :second)

  @doc """
  The payment mode a member may choose at checkout. `online` needs an
  available provider; `on_account` needs the business to allow it.
  """
  @spec checkout_mode(term(), %{online_available: boolean(), on_account_allowed: boolean()}) ::
          {:ok, atom()} | {:error, atom()}
  def checkout_mode(mode, facts) do
    case parse(mode, @online_modes) do
      {:ok, :online} ->
        if facts.online_available, do: {:ok, :online}, else: {:error, :online_payment_unavailable}

      {:ok, :on_account} ->
        if facts.on_account_allowed,
          do: {:ok, :on_account},
          else: {:error, :on_account_not_allowed}

      {:ok, mode} ->
        {:ok, mode}

      :error ->
        {:error, :invalid_payment_mode}
    end
  end

  @doc "A desk payment method (cash, card at the terminal, transfer, other)."
  @spec desk_method(term()) :: {:ok, atom()} | {:error, :invalid_payment_method}
  def desk_method(method) do
    case parse(method, @desk_methods) do
      {:ok, method} -> {:ok, method}
      :error -> {:error, :invalid_payment_method}
    end
  end

  @doc "An attribution source, `direct` when missing or unknown."
  @spec source(term()) :: atom()
  def source(value) do
    case parse(value, @sources) do
      {:ok, source} -> source
      :error -> :direct
    end
  end

  defp parse(value, allowed) when is_atom(value) and not is_nil(value),
    do: if(value in allowed, do: {:ok, value}, else: :error)

  defp parse(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  defp parse(_value, _allowed), do: :error
end
