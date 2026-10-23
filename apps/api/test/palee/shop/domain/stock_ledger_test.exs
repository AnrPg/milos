defmodule Palee.Shop.Domain.StockLedgerTest do
  @moduledoc """
  Property-style checks of the stock ledger (ADR-190): thousands of random
  movement sequences, seeded so a failure is reproducible.
  """

  use ExUnit.Case, async: true

  alias Palee.Shop.Domain.StockLedger

  @runs 400
  @steps 60

  defp random_movement do
    case :rand.uniform(8) do
      1 -> %{kind: :receive, quantity: :rand.uniform(20)}
      2 -> %{kind: :sale, quantity: -:rand.uniform(10)}
      3 -> %{kind: :reserve, quantity: :rand.uniform(6)}
      4 -> %{kind: :release, quantity: :rand.uniform(6)}
      5 -> %{kind: :refund_restock, quantity: :rand.uniform(3)}
      6 -> %{kind: :adjustment, quantity: Enum.random([-5, -2, -1, 1, 3]), reason: :damage}
      7 -> %{kind: :transfer, quantity: Enum.random([-4, -1, 2, 5])}
      8 -> %{kind: :adjustment, quantity: 1, reason: nil}
    end
  end

  defp sequences(seed) do
    :rand.seed(:exsss, {seed, seed * 7, seed * 13})
    for _run <- 1..@runs, do: for(_step <- 1..@steps, do: random_movement())
  end

  test "no prefix of any sequence breaks the invariants, whatever is refused" do
    for movements <- sequences(1) do
      Enum.reduce(movements, StockLedger.empty(), fn movement, level ->
        case StockLedger.apply_movement(level, movement) do
          {:ok, next} ->
            assert StockLedger.consistent?(next)
            assert next.on_hand >= 0 and next.reserved >= 0 and next.reserved <= next.on_hand
            next

          {:error, _reason} ->
            level
        end
      end)
    end
  end

  test "the projection equals the sum of the accepted ledger rows (on hand) and reservations" do
    for movements <- sequences(2) do
      {level, accepted} =
        Enum.reduce(movements, {StockLedger.empty(), []}, fn movement, {level, accepted} ->
          case StockLedger.apply_movement(level, movement) do
            {:ok, next} -> {next, [movement | accepted]}
            {:error, _reason} -> {level, accepted}
          end
        end)

      on_hand =
        accepted
        |> Enum.reject(&(&1.kind in [:reserve, :release]))
        |> Enum.map(& &1.quantity)
        |> Enum.sum()

      reserved =
        accepted
        |> Enum.filter(&(&1.kind in [:reserve, :release]))
        |> Enum.map(&if(&1.kind == :reserve, do: &1.quantity, else: -&1.quantity))
        |> Enum.sum()

      assert level == %{on_hand: on_hand, reserved: reserved}
      # Replaying only the accepted rows reproduces the same level.
      assert StockLedger.replay(Enum.reverse(accepted)) == {:ok, level}
    end
  end

  test "a sale or reservation never takes more than is available (never oversold)" do
    for movements <- sequences(3) do
      Enum.reduce(movements, StockLedger.empty(), fn movement, level ->
        result = StockLedger.apply_movement(level, movement)

        if movement.kind in [:sale, :reserve] do
          wanted = abs(movement.quantity)

          case result do
            {:ok, _next} -> assert wanted <= StockLedger.available(level)
            {:error, :insufficient_stock} -> assert wanted > StockLedger.available(level)
            {:error, _other} -> :ok
          end
        end

        case result do
          {:ok, next} -> next
          {:error, _reason} -> level
        end
      end)
    end
  end

  test "movement shapes are checked" do
    assert {:error, :invalid_quantity} = StockLedger.validate(%{kind: :receive, quantity: 0})
    assert {:error, :invalid_quantity} = StockLedger.validate(%{kind: :sale, quantity: 2})

    assert {:error, :adjustment_reason_required} =
             StockLedger.validate(%{kind: :adjustment, quantity: 1})

    assert :ok = StockLedger.validate(%{kind: :adjustment, quantity: -1, reason: :loss})
    assert {:error, :invalid_movement} = StockLedger.validate(%{kind: :steal, quantity: 1})
  end

  test "a recount yields the adjustment to the counted stock and never goes under the reserved" do
    level = %{on_hand: 10, reserved: 3}
    assert {:ok, -4} = StockLedger.recount(level, 6)
    assert {:ok, nil} = StockLedger.recount(level, 10)
    assert {:ok, 5} = StockLedger.recount(level, 15)
    assert {:error, :insufficient_stock} = StockLedger.recount(level, 2)
  end

  test "a transfer is two opposite rows between two branches" do
    assert {:ok, [%{quantity: -3, location_id: "a"}, %{quantity: 3, location_id: "b"}]} =
             StockLedger.transfer(3, "a", "b")

    assert {:error, :same_location} = StockLedger.transfer(3, "a", "a")
    assert {:error, :invalid_quantity} = StockLedger.transfer(0, "a", "b")
  end
end
