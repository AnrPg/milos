defmodule MilosTraining.Inventory.InventoryPoliciesTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Inventory.Domain.{InventoryReport, MachinePolicy, StockPolicy}

  @now ~U[2026-10-14 12:00:00Z]

  defp used(days_ago, quantity \\ 1),
    do: %{kind: :consume, quantity: quantity, occurred_at: DateTime.add(@now, -days_ago * 86_400)}

  describe "StockPolicy.assess/3" do
    test "two of a daily item is critical; two of a rare item is fine" do
      assert %{status: :critical, days_left: 2.0} =
               StockPolicy.assess(%{quantity: 2, consumption_speed: :fast}, [], @now)

      assert %{status: :ok} =
               StockPolicy.assess(%{quantity: 2, consumption_speed: :slow}, [], @now)

      assert %{status: :low} =
               StockPolicy.assess(%{quantity: 2, consumption_speed: :regular}, [], @now)

      assert %{status: :out} =
               StockPolicy.assess(%{quantity: 0, consumption_speed: :slow}, [], @now)
    end

    test "learns the real pace from recorded uses" do
      # Marked slow, but used about once every two days for a month.
      movements =
        for day <- [30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2], do: used(day)

      assert %{status: :critical, basis: :observed} =
               StockPolicy.assess(%{quantity: 3, consumption_speed: :slow}, movements, @now)
    end

    test "a reorder level raises the status to low" do
      assert %{status: :low} =
               StockPolicy.assess(
                 %{quantity: 5, consumption_speed: :slow, reorder_level: 5},
                 [],
                 @now
               )
    end

    test "alerts only when the status gets worse" do
      assert StockPolicy.alert?(:ok, :low)
      assert StockPolicy.alert?(:low, :critical)
      refute StockPolicy.alert?(:critical, :low)
      refute StockPolicy.alert?(:ok, :ok)
    end

    test "cannot use more than what is in stock" do
      assert {:error, :not_enough_stock} = StockPolicy.apply_movement(1, :consume, 2)
      assert {:ok, 5} = StockPolicy.apply_movement(2, :restock, 3)
      assert {:ok, 4} = StockPolicy.apply_movement(9, :adjust, 4)
    end
  end

  describe "MachinePolicy" do
    test "the log moves the machine's state" do
      assert {:ok, :needs_attention} = MachinePolicy.next_status(:working, :issue)
      assert {:ok, :out_of_order} = MachinePolicy.next_status(:needs_attention, :out_of_order)
      assert {:ok, :out_of_order} = MachinePolicy.next_status(:out_of_order, :issue)
      assert {:ok, :working} = MachinePolicy.next_status(:out_of_order, :repaired)

      assert {:ok, :needs_attention} =
               MachinePolicy.next_status(:needs_attention, :repair_requested)

      assert {:error, :machine_retired} = MachinePolicy.next_status(:retired, :note)

      assert {:ok, :out_of_order} =
               MachinePolicy.next_status(:working, :issue, %{severity: :safety})

      assert {:ok, :out_of_order} = MachinePolicy.next_status(:working, :issue, %{usable: false})

      assert {:ok, :needs_attention} =
               MachinePolicy.next_status(:working, :issue, %{severity: :low})

      assert MachinePolicy.alert?(:repair_requested)
      refute MachinePolicy.alert?(:maintenance)
    end

    test "service falls due after the interval" do
      machine = %{service_interval_days: 90, last_serviced_on: ~D[2026-07-01]}
      assert MachinePolicy.service_due?(machine, ~D[2026-09-29])
      refute MachinePolicy.service_due?(machine, ~D[2026-09-28])
      refute MachinePolicy.service_due?(%{service_interval_days: nil}, ~D[2026-09-29])
    end
  end

  test "the report adds purchases and machine costs per month" do
    supply = %{
      id: "s1",
      name: "Chalk",
      unit: "block",
      unit_price_cents: 300,
      movements: [
        %{
          kind: :restock,
          quantity: 10,
          total_cents: nil,
          unit_price_cents: 250,
          occurred_at: ~U[2026-09-03 10:00:00Z]
        },
        %{kind: :consume, quantity: 4, occurred_at: ~U[2026-10-02 10:00:00Z]},
        %{kind: :restock, quantity: 2, total_cents: 700, occurred_at: ~U[2026-10-05 10:00:00Z]}
      ]
    }

    events = [%{cost_cents: 5_000, occurred_at: ~U[2026-10-10 10:00:00Z]}]
    report = InventoryReport.build([supply], events, ~D[2026-10-14], 2)

    assert [
             %{month: "2026-09", total_cents: 2_500},
             %{month: "2026-10", supplies_cents: 700, machines_cents: 5_000, total_cents: 5_700}
           ] =
             report.expenses

    assert [%{consumed: 4, spent_cents: 3_200, purchased: 12}] = report.supplies
    assert report.totals == %{supplies_cents: 3_200, machines_cents: 5_000}
  end
end
