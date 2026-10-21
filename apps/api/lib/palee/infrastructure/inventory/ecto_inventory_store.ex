defmodule Palee.Infrastructure.Inventory.EctoInventoryStore do
  @moduledoc "Ecto adapter for the gym's inventory (ADR-104)."

  @behaviour Palee.Inventory.Ports.InventoryStore

  import Ecto.Query

  alias Palee.Inventory.Domain.{MachinePolicy, StockPolicy}
  alias Palee.Inventory.{Machine, MachineEvent, Supply, SupplyMovement, SupplyReport}
  alias Palee.Repo

  @machine_fields [:id | Machine.fields() -- [:organization_id]] ++ [:inserted_at]
  @event_fields [
    :id,
    :machine_id,
    :user_id,
    :kind,
    :severity,
    :symptom,
    :usable,
    :body,
    :cost_cents,
    :occurred_at
  ]
  @supply_fields [:id, :quantity, :stock_status, :archived_at | Supply.editable()]
  @report_fields [
    :id,
    :supply_id,
    :user_id,
    :level,
    :seen_quantity,
    :place,
    :note,
    :reported_at,
    :resolved_at,
    :resolved_by_id
  ]
  @movement_fields [
    :id,
    :supply_id,
    :user_id,
    :kind,
    :quantity,
    :unit_price_cents,
    :total_cents,
    :note,
    :occurred_at
  ]

  @impl true
  def list_machines(%{organization_id: organization_id}, filters) do
    Machine
    |> where([m], m.organization_id == ^organization_id)
    |> archived(filters[:include_archived])
    |> order_by([m], asc: m.category, asc: m.name)
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @machine_fields))
  end

  @impl true
  def get_machine(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Machine{} = machine <- one(Machine, organization_id, id) do
      Map.take(machine, @machine_fields)
    else
      _missing -> nil
    end
  end

  @impl true
  def save_machine(%{organization_id: organization_id}, nil, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Machine.changeset()
    |> Repo.insert()
    |> result(@machine_fields)
  end

  def save_machine(%{organization_id: organization_id}, id, attrs) do
    case cast_one(Machine, organization_id, id) do
      nil -> {:error, :not_found}
      machine -> machine |> Machine.changeset(attrs) |> Repo.update() |> result(@machine_fields)
    end
  end

  @impl true
  def add_machine_event(%{organization_id: organization_id}, machine_id, attrs) do
    Repo.transaction(fn ->
      with %Machine{} = machine <-
             locked(Machine, organization_id, machine_id) || {:error, :not_found},
           {:ok, status} <- MachinePolicy.next_status(machine.status, attrs.kind, attrs),
           {:ok, event} <-
             attrs
             |> Map.merge(%{organization_id: organization_id, machine_id: machine.id})
             |> MachineEvent.changeset()
             |> Repo.insert(),
           {:ok, updated} <-
             machine
             |> Machine.changeset(machine_changes(status, attrs))
             |> Repo.update() do
        %{
          machine: Map.take(updated, @machine_fields),
          event: Map.take(event, @event_fields),
          previous_status: machine.status
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp machine_changes(status, %{kind: kind, occurred_at: at})
       when kind in [:maintenance, :repaired],
       do: %{status: status, last_serviced_on: DateTime.to_date(at)}

  defp machine_changes(:retired, _attrs), do: %{status: :retired, archived_at: DateTime.utc_now()}
  defp machine_changes(status, _attrs), do: %{status: status}

  @impl true
  def list_machine_events(%{organization_id: organization_id}, filters) do
    MachineEvent
    |> where([e], e.organization_id == ^organization_id)
    |> filter(:machine_id, filters[:machine_id])
    |> since(filters[:from])
    |> order_by([e], desc: e.occurred_at)
    |> limit(^(filters[:limit] || 200))
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @event_fields))
  end

  @impl true
  def list_supplies(%{organization_id: organization_id}, filters) do
    Supply
    |> where([s], s.organization_id == ^organization_id)
    |> archived(filters[:include_archived])
    |> order_by([s], asc: s.name)
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @supply_fields))
  end

  @impl true
  def get_supply(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Supply{} = supply <- one(Supply, organization_id, id) do
      Map.take(supply, @supply_fields)
    else
      _missing -> nil
    end
  end

  @impl true
  def save_supply(%{organization_id: organization_id}, nil, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Supply.changeset()
    |> Repo.insert()
    |> result(@supply_fields)
  end

  def save_supply(%{organization_id: organization_id}, id, attrs) do
    case cast_one(Supply, organization_id, id) do
      nil -> {:error, :not_found}
      supply -> supply |> Supply.changeset(attrs) |> Repo.update() |> result(@supply_fields)
    end
  end

  @impl true
  def record_movement(%{organization_id: organization_id}, supply_id, attrs) do
    Repo.transaction(fn ->
      with %Supply{} = supply <-
             locked(Supply, organization_id, supply_id) || {:error, :not_found},
           {:ok, quantity} <-
             StockPolicy.apply_movement(supply.quantity, attrs.kind, attrs.quantity),
           {:ok, movement} <-
             attrs
             |> Map.merge(%{organization_id: organization_id, supply_id: supply.id})
             |> SupplyMovement.changeset()
             |> Repo.insert(),
           {:ok, updated} <-
             supply |> Supply.changeset(supply_changes(quantity, attrs)) |> Repo.update() do
        if attrs.kind == :restock, do: resolve_reports(organization_id, supply.id, attrs)

        %{
          supply: Map.take(updated, @supply_fields),
          movement: Map.take(movement, @movement_fields)
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # A restock at a new price updates the item's price.
  defp supply_changes(quantity, %{kind: :restock, unit_price_cents: price})
       when is_integer(price),
       do: %{quantity: quantity, unit_price_cents: price}

  defp supply_changes(quantity, _attrs), do: %{quantity: quantity}

  defp resolve_reports(organization_id, supply_id, attrs) do
    SupplyReport
    |> where([r], r.organization_id == ^organization_id and r.supply_id == ^supply_id)
    |> where([r], is_nil(r.resolved_at))
    |> Repo.update_all(set: [resolved_at: attrs.occurred_at, resolved_by_id: attrs[:user_id]])
  end

  @impl true
  def add_supply_report(%{organization_id: organization_id}, supply_id, attrs) do
    case cast_one(Supply, organization_id, supply_id) do
      %Supply{archived_at: nil} = supply ->
        attrs
        |> Map.merge(%{organization_id: organization_id, supply_id: supply.id})
        |> SupplyReport.changeset()
        |> Repo.insert()
        |> result(@report_fields)

      _missing ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_supply_reports(%{organization_id: organization_id}, filters) do
    SupplyReport
    |> where([r], r.organization_id == ^organization_id)
    |> supply_ids(filters[:supply_ids])
    |> open_only(filters[:open])
    |> order_by([r], desc: r.reported_at)
    |> limit(^(filters[:limit] || 500))
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @report_fields))
  end

  defp open_only(query, true), do: where(query, [r], is_nil(r.resolved_at))
  defp open_only(query, _all), do: query

  @impl true
  def list_movements(%{organization_id: organization_id}, filters) do
    SupplyMovement
    |> where([m], m.organization_id == ^organization_id)
    |> filter(:supply_id, filters[:supply_id])
    |> supply_ids(filters[:supply_ids])
    |> since(filters[:from])
    |> order_by([m], desc: m.occurred_at)
    |> limit(^(filters[:limit] || 5000))
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @movement_fields))
  end

  defp one(schema, organization_id, id),
    do: schema |> where([r], r.organization_id == ^organization_id and r.id == ^id) |> Repo.one()

  defp cast_one(schema, organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> one(schema, organization_id, id)
      :error -> nil
    end
  end

  defp locked(schema, organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        schema
        |> where([r], r.organization_id == ^organization_id and r.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      :error ->
        nil
    end
  end

  defp archived(query, true), do: query
  defp archived(query, _include), do: where(query, [r], is_nil(r.archived_at))

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  defp supply_ids(query, nil), do: query
  defp supply_ids(query, ids), do: where(query, [m], m.supply_id in ^ids)

  defp since(query, nil), do: query
  defp since(query, %DateTime{} = from), do: where(query, [r], r.occurred_at >= ^from)

  defp result({:ok, value}, fields), do: {:ok, Map.take(value, fields)}
  defp result(error, _fields), do: error
end
