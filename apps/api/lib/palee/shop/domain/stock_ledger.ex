defmodule Palee.Shop.Domain.StockLedger do
  @moduledoc """
  The stock ledger's arithmetic (ADR-190), pure. A level is
  `%{on_hand, reserved}` for one variant at one branch; a movement is
  `%{kind, quantity}`.

  | kind | quantity | effect |
  |---|---|---|
  | `receive`, `refund_restock` | > 0 | on hand + q |
  | `sale` | < 0 | on hand + q (q is negative) |
  | `adjustment` (with a reason), `transfer` | ≠ 0 | on hand + q |
  | `reserve` | > 0 | reserved + q |
  | `release` | > 0 | reserved − q |

  Invariants, for every prefix of the ledger:
  `on_hand >= 0`, `reserved >= 0`, `reserved <= on_hand`. A movement that
  would break one is refused (`:insufficient_stock`), so stock is never
  oversold: a sale or reservation takes only what is available
  (`on_hand - reserved`), and a reserved unit is sold by releasing it and
  selling it in the same transaction. The database enforces the same
  invariants with a check constraint on the projection.
  """

  @kinds [:receive, :sale, :refund_restock, :adjustment, :transfer, :reserve, :release]
  @adjustment_reasons [:recount, :damage, :loss, :return, :other]

  @type kind ::
          :receive | :sale | :refund_restock | :adjustment | :transfer | :reserve | :release
  @type level :: %{on_hand: non_neg_integer(), reserved: non_neg_integer()}
  @type movement :: %{
          required(:kind) => kind(),
          required(:quantity) => integer(),
          optional(any()) => any()
        }

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec adjustment_reasons() :: [atom()]
  def adjustment_reasons, do: @adjustment_reasons

  @doc "The kinds staff record by hand (sales, reservations and restocks come from orders)."
  @spec manual_kinds() :: [kind()]
  def manual_kinds, do: [:receive, :adjustment, :transfer]

  @doc "An empty level."
  @spec empty() :: level()
  def empty, do: %{on_hand: 0, reserved: 0}

  @doc "What can still be sold or reserved."
  @spec available(level()) :: integer()
  def available(%{on_hand: on_hand, reserved: reserved}), do: on_hand - reserved

  @doc "Checks a movement's shape (sign, reason) before it is applied."
  @spec validate(map()) :: :ok | {:error, atom()}
  def validate(%{kind: kind, quantity: quantity} = movement) when is_integer(quantity) do
    cond do
      kind not in @kinds ->
        {:error, :invalid_movement}

      kind in [:receive, :refund_restock, :reserve, :release] and quantity <= 0 ->
        {:error, :invalid_quantity}

      kind == :sale and quantity >= 0 ->
        {:error, :invalid_quantity}

      kind in [:adjustment, :transfer] and quantity == 0 ->
        {:error, :invalid_quantity}

      kind == :adjustment and Map.get(movement, :reason) not in @adjustment_reasons ->
        {:error, :adjustment_reason_required}

      true ->
        :ok
    end
  end

  def validate(_movement), do: {:error, :invalid_movement}

  @doc "The level after `movement`, or why it cannot happen."
  @spec apply_movement(level(), movement()) :: {:ok, level()} | {:error, atom()}
  def apply_movement(
        %{on_hand: on_hand, reserved: reserved} = level,
        %{kind: kind, quantity: q} = movement
      ) do
    with :ok <- validate(movement) do
      next =
        case kind do
          :reserve -> %{level | reserved: reserved + q}
          :release -> %{level | reserved: reserved - q}
          _on_hand_change -> %{level | on_hand: on_hand + q}
        end

      if consistent?(next), do: {:ok, next}, else: {:error, :insufficient_stock}
    end
  end

  @doc "Whether a level satisfies the ledger invariants."
  @spec consistent?(level()) :: boolean()
  def consistent?(%{on_hand: on_hand, reserved: reserved}),
    do: on_hand >= 0 and reserved >= 0 and reserved <= on_hand

  @doc """
  Replays movements from an empty level; `{:ok, level}` or the first
  movement that broke an invariant.
  """
  @spec replay([movement()]) :: {:ok, level()} | {:error, atom(), movement()}
  def replay(movements) do
    Enum.reduce_while(movements, {:ok, empty()}, fn movement, {:ok, level} ->
      case apply_movement(level, movement) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason, movement}}
      end
    end)
  end

  @doc "The adjustment that brings on-hand stock to a counted value (nil when equal)."
  @spec recount(level(), non_neg_integer()) :: {:ok, integer() | nil} | {:error, atom()}
  def recount(%{on_hand: on_hand, reserved: reserved}, counted)
      when is_integer(counted) and counted >= 0 do
    cond do
      counted < reserved -> {:error, :insufficient_stock}
      counted == on_hand -> {:ok, nil}
      true -> {:ok, counted - on_hand}
    end
  end

  def recount(_level, _counted), do: {:error, :invalid_quantity}

  @doc """
  The two movements of a transfer of `quantity` units between branches:
  out of `from` and into `to`.
  """
  @spec transfer(pos_integer(), term(), term()) ::
          {:ok, [%{kind: :transfer, quantity: integer(), location_id: term()}]} | {:error, atom()}
  def transfer(quantity, from, to) when is_integer(quantity) and quantity > 0 and from != to,
    do:
      {:ok,
       [
         %{kind: :transfer, quantity: -quantity, location_id: from},
         %{kind: :transfer, quantity: quantity, location_id: to}
       ]}

  def transfer(quantity, _from, _to) when is_integer(quantity) and quantity > 0,
    do: {:error, :same_location}

  def transfer(_quantity, _from, _to), do: {:error, :invalid_quantity}

  @doc "Sums levels across branches."
  @spec total([level()]) :: level()
  def total(levels) do
    Enum.reduce(levels, empty(), fn level, acc ->
      %{on_hand: acc.on_hand + level.on_hand, reserved: acc.reserved + level.reserved}
    end)
  end
end
