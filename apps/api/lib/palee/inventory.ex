defmodule Palee.Inventory do
  @moduledoc """
  What the gym owns (ADR-104): machines (training machines and appliances)
  with their state and maintenance log, and consumables with their stock,
  where they are bought, and how fast they go.
  """

  alias Palee.Inventory.Domain.{
    InventoryDigest,
    InventoryReport,
    MachinePolicy,
    StockPolicy
  }

  alias Palee.Inventory.InventoryStore

  # ── Machines ────────────────────────────────────────────────────────────

  def list_machines(context, today \\ nil) do
    today = today || gym_today(context)

    context
    |> InventoryStore.list_machines(%{})
    |> Enum.map(&with_service(&1, today))
  end

  def get_machine(context, id), do: InventoryStore.get_machine(context, id)

  def save_machine(context, id, attrs) do
    attrs = Map.drop(attrs, [:status, :archived_at, :organization_id])

    with {:ok, machine} <- InventoryStore.save_machine(context, id, attrs) do
      {:ok, with_service(machine, gym_today(context))}
    end
  end

  @doc "Logs an event and moves the machine's state (MachinePolicy)."
  def log_machine_event(context, machine_id, params, now \\ DateTime.utc_now()) do
    with {:ok, kind} <- event_kind(params[:kind]) do
      InventoryStore.add_machine_event(context, machine_id, %{
        kind: kind,
        severity: params[:severity],
        symptom: params[:symptom],
        usable: params[:usable],
        body: params[:body],
        cost_cents: params[:cost_cents],
        user_id: context.user_id,
        occurred_at: params[:occurred_at] || now
      })
    end
  end

  def list_machine_events(context, machine_id),
    do: InventoryStore.list_machine_events(context, %{machine_id: machine_id})

  def alert_machine_event?(kind), do: MachinePolicy.alert?(kind)

  defp event_kind(kind) when is_atom(kind) and not is_nil(kind),
    do: if(kind in MachinePolicy.kinds(), do: {:ok, kind}, else: {:error, :invalid_machine_event})

  defp event_kind(kind) when is_binary(kind) do
    case Enum.find(MachinePolicy.kinds(), &(Atom.to_string(&1) == kind)) do
      nil -> {:error, :invalid_machine_event}
      found -> {:ok, found}
    end
  end

  defp event_kind(_kind), do: {:error, :invalid_machine_event}

  defp with_service(machine, today) do
    Map.merge(machine, %{
      next_service_on: MachinePolicy.next_service_on(machine),
      service_due: machine.status != :retired and MachinePolicy.service_due?(machine, today)
    })
  end

  # ── Consumables ─────────────────────────────────────────────────────────

  @doc "Consumables with their stock assessment and open \"running low\" reports."
  def list_supplies(context, now \\ DateTime.utc_now()) do
    supplies = InventoryStore.list_supplies(context, %{})
    ids = Enum.map(supplies, & &1.id)
    movements = recent_movements(context, ids, now)
    reports = open_reports(context, ids)

    Enum.map(supplies, fn supply ->
      supply
      |> with_stock(Map.get(movements, supply.id, []), now)
      |> Map.put(:open_reports, Map.get(reports, supply.id, []))
    end)
  end

  @doc "Someone on the team flags a consumable as running low, with a note."
  def report_low(context, supply_id, params, now \\ DateTime.utc_now()) do
    with {:ok, report} <-
           InventoryStore.add_supply_report(context, supply_id, %{
             user_id: context.user_id,
             level: params[:level] || :running_low,
             seen_quantity: params[:seen_quantity],
             place: params[:place],
             note: params[:note],
             reported_at: now
           }) do
      supply = Enum.find(list_supplies(context, now), &(&1.id == report.supply_id))
      {:ok, %{report: report, supply: supply}}
    end
  end

  def list_supply_reports(context, supply_id),
    do: InventoryStore.list_supply_reports(context, %{supply_ids: [supply_id]})

  defp open_reports(_context, []), do: %{}

  defp open_reports(context, ids) do
    context
    |> InventoryStore.list_supply_reports(%{supply_ids: ids, open: true})
    |> Enum.group_by(& &1.supply_id)
  end

  def save_supply(context, id, attrs) do
    attrs = Map.take(attrs, Palee.Inventory.Supply.editable() ++ [:quantity])
    attrs = if id, do: Map.delete(attrs, :quantity), else: attrs

    with {:ok, supply} <- InventoryStore.save_supply(context, id, attrs) do
      refresh_stock(context, supply, DateTime.utc_now())
    end
  end

  def archive_supply(context, id),
    do: InventoryStore.save_supply(context, id, %{archived_at: DateTime.utc_now()})

  def archive_machine(context, id),
    do: InventoryStore.save_machine(context, id, %{archived_at: DateTime.utc_now()})

  @doc """
  Records a restock, a use or a recount; returns the supply with its stock
  assessment and the status it had before, so callers can alert on a drop.
  """
  def record_movement(context, supply_id, params, now \\ DateTime.utc_now()) do
    with {:ok, kind} <- movement_kind(params[:kind]),
         %{} = before <- InventoryStore.get_supply(context, supply_id) || {:error, :not_found},
         {:ok, %{supply: supply, movement: movement}} <-
           InventoryStore.record_movement(context, supply_id, %{
             kind: kind,
             quantity: params[:quantity],
             unit_price_cents: params[:unit_price_cents],
             total_cents: params[:total_cents],
             note: params[:note],
             user_id: context.user_id,
             occurred_at: params[:occurred_at] || now
           }),
         {:ok, supply} <- refresh_stock(context, supply, now) do
      {:ok, %{supply: supply, movement: movement, previous_status: before.stock_status}}
    end
  end

  def list_movements(context, supply_id),
    do: InventoryStore.list_movements(context, %{supply_id: supply_id, limit: 200})

  def stock_alert?(previous, current), do: StockPolicy.alert?(previous, current)

  defp refresh_stock(context, supply, now) do
    movements = context |> recent_movements([supply.id], now) |> Map.get(supply.id, [])
    assessed = with_stock(supply, movements, now)

    if assessed.stock.status != supply.stock_status do
      with {:ok, _saved} <-
             InventoryStore.save_supply(context, supply.id, %{stock_status: assessed.stock.status}) do
        {:ok, %{assessed | stock_status: assessed.stock.status}}
      end
    else
      {:ok, assessed}
    end
  end

  defp recent_movements(_context, [], _now), do: %{}

  defp recent_movements(context, ids, now) do
    context
    |> InventoryStore.list_movements(%{
      supply_ids: ids,
      from: DateTime.add(now, -StockPolicy.window_days() * 86_400, :second)
    })
    |> Enum.group_by(& &1.supply_id)
  end

  defp with_stock(supply, movements, now),
    do: Map.put(supply, :stock, StockPolicy.assess(supply, movements, now))

  defp movement_kind(kind) when kind in [:restock, :consume, :adjust], do: {:ok, kind}

  defp movement_kind(kind) when kind in ["restock", "consume", "adjust"],
    do: {:ok, String.to_existing_atom(kind)}

  defp movement_kind(_kind), do: {:error, :invalid_movement}

  # ── Daily summary ───────────────────────────────────────────────────────

  @doc "What needs attention today, or nil (InventoryDigest)."
  def digest(context, now \\ DateTime.utc_now()) do
    supplies = list_supplies(context, now)
    names = Map.new(supplies, &{&1.id, &1.name})

    reports =
      supplies
      |> Enum.flat_map(& &1.open_reports)
      |> Enum.map(&Map.put(&1, :supply_name, names[&1.supply_id]))

    notes =
      InventoryStore.list_machine_events(context, %{from: DateTime.add(now, -86_400, :second)})
      |> Enum.filter(&(&1.kind in [:note, :issue, :out_of_order, :repair_requested]))

    InventoryDigest.build(
      %{
        supplies: supplies,
        machines: list_machines(context, DateTime.to_date(now)),
        reports: reports,
        notes: notes
      },
      DateTime.to_date(now)
    )
  end

  # ── Report ──────────────────────────────────────────────────────────────

  @doc "Consumption, spend per item and monthly inventory expenses."
  def report(context, months \\ 12, today \\ nil) do
    today = today || gym_today(context)
    months = months |> max(1) |> min(36)
    from = today |> Date.beginning_of_month() |> Date.shift(month: -(months - 1))
    from_at = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    supplies = InventoryStore.list_supplies(context, %{include_archived: true})

    movements =
      context
      |> InventoryStore.list_movements(%{
        supply_ids: Enum.map(supplies, & &1.id),
        from: from_at,
        limit: 50_000
      })
      |> Enum.group_by(& &1.supply_id)

    events = InventoryStore.list_machine_events(context, %{from: from_at, limit: 50_000})

    supplies
    |> Enum.map(&Map.put(&1, :movements, Map.get(movements, &1.id, [])))
    |> Enum.filter(&(is_nil(&1.archived_at) or &1.movements != []))
    |> InventoryReport.build(events, today, months)
  end

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: Palee.Inventory.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  # ADR-179: a machine's service date and the report's months follow the gym's day.
  defp gym_today(%{organization_id: organization_id}) when is_binary(organization_id),
    do: Palee.Organizations.local_today(organization_id)

  defp gym_today(_context), do: Date.utc_today()
end
