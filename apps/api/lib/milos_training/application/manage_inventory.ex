defmodule MilosTraining.Application.ManageInventory do
  @moduledoc """
  Inventory changes that alert people (ADR-104): an issue, outage or repair
  call on a machine, and a consumable whose stock drops to low, critical or
  out. Everyone who looks after the inventory (owners, admins, front desk) is
  told, except the person who made the change.
  """

  alias MilosTraining.{Inventory, Notifications, Organizations}

  # Who only reports (coaches, janitors) may add notes, issues and outages;
  # services, repairs, repair calls and retiring stay with who manages.
  @reporter_kinds ["note", "issue", "out_of_order", :note, :issue, :out_of_order]

  def log_machine_event(context, machine_id, params) do
    with :ok <- may_log(context, params[:kind]),
         {:ok, %{machine: machine, event: event} = result} <-
           Inventory.log_machine_event(context, machine_id, params) do
      if Inventory.alert_machine_event?(event.kind) do
        notify(context, "inventory_repair_needed", %{
          machine_id: machine.id,
          machine_name: machine.name,
          kind: event.kind,
          severity: event.severity,
          symptom: event.symptom,
          body: event.body
        })
      end

      {:ok, result}
    end
  end

  def record_movement(context, supply_id, params) do
    with {:ok, %{supply: supply, previous_status: before} = result} <-
           Inventory.record_movement(context, supply_id, params) do
      if Inventory.stock_alert?(before, supply.stock.status) do
        notify(context, "inventory_stock_low", %{
          supply_id: supply.id,
          supply_name: supply.name,
          status: supply.stock.status,
          quantity: supply.quantity,
          days_left: supply.stock.days_left
        })
      end

      {:ok, result}
    end
  end

  defp may_log(context, kind) do
    if Organizations.can?(context, :manage_inventory) or kind in @reporter_kinds,
      do: :ok,
      else: {:error, :forbidden}
  end

  @doc "A janitor or anyone on the team reports a consumable running low."
  def report_low(context, supply_id, params) do
    with {:ok, %{supply: supply, report: report}} = result <-
           Inventory.report_low(context, supply_id, params) do
      notify(context, "inventory_stock_low", %{
        supply_id: supply.id,
        supply_name: supply.name,
        status: :reported,
        level: report.level,
        place: report.place,
        quantity: supply.quantity,
        note: report.note
      })

      result
    end
  end

  @doc "The daily summary for everyone who looks after the inventory."
  def send_digest(context, now \\ DateTime.utc_now()) do
    case Inventory.digest(context, now) do
      nil ->
        :ok

      digest ->
        notify(
          Map.put(context, :user_id, nil),
          "inventory_digest",
          Map.put(digest, :date, DateTime.to_date(now))
        )
    end
  end

  defp notify(context, type, payload) do
    context.organization_id
    |> Organizations.list_user_ids_with_capability(:manage_inventory)
    |> Enum.reject(&(&1 == context.user_id))
    |> Enum.each(fn user_id ->
      Notifications.process_event(
        type,
        Map.merge(payload, %{user_id: user_id, organization_id: context.organization_id})
      )
    end)
  end
end
