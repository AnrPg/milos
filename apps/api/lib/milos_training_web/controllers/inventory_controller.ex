defmodule MilosTrainingWeb.InventoryController do
  @moduledoc "The gym's inventory: machines and consumables (ADR-104)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ManageInventory
  alias MilosTraining.{Identity, Inventory, Organizations}
  alias MilosTrainingWeb.Schemas.Inventory, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Inventory"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  # ── Machines ────────────────────────────────────────────────────────────

  operation(:machines,
    summary: "Machines and appliances, with state and service due",
    responses: [ok: {"Machines", "application/json", S.many(:machines, S.machine())}]
  )

  # Who only reports (coaches, janitors) sees no prices, shops or contacts.
  @money_fields [
    :purchase_price_cents,
    :unit_price_cents,
    :shop,
    :url,
    :service_contact,
    :serial_number
  ]

  def machines(conn, _params) do
    context = conn.assigns.tenant_context
    json(conn, %{machines: context |> Inventory.list_machines() |> redact(context)})
  end

  operation(:create_machine,
    summary: "Add a machine or appliance",
    request_body: S.body(S.machine_body()),
    responses: [created: {"Machine", "application/json", S.one(:machine, S.machine())}]
  )

  def create_machine(conn, _params) do
    with {:ok, machine} <-
           Inventory.save_machine(conn.assigns.tenant_context, nil, conn.body_params) do
      conn |> put_status(:created) |> json(%{machine: machine})
    end
  end

  operation(:update_machine,
    summary: "Edit a machine's details",
    parameters: [@id],
    request_body: S.body(S.machine_body()),
    responses: [ok: {"Machine", "application/json", S.one(:machine, S.machine())}]
  )

  def update_machine(conn, %{id: id}) do
    with {:ok, machine} <-
           Inventory.save_machine(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{machine: machine})
    end
  end

  operation(:archive_machine,
    summary: "Remove a machine from the list (its log is kept)",
    parameters: [@id],
    responses: [ok: {"Machine", "application/json", S.one(:machine, S.machine())}]
  )

  def archive_machine(conn, %{id: id}) do
    with {:ok, machine} <- Inventory.archive_machine(conn.assigns.tenant_context, id) do
      json(conn, %{machine: machine})
    end
  end

  operation(:machine_events,
    summary: "A machine's log",
    parameters: [@id],
    responses: [ok: {"Events", "application/json", S.many(:events, S.machine_event())}]
  )

  def machine_events(conn, %{id: id}) do
    events = Inventory.list_machine_events(conn.assigns.tenant_context, id)
    json(conn, %{events: with_nicknames(events)})
  end

  operation(:log_machine_event,
    summary: "Log a note, issue, outage, repair call, service or repair",
    parameters: [@id],
    request_body: S.body(S.machine_event_body()),
    responses: [
      created:
        {"Logged", "application/json",
         %Schema{
           type: :object,
           properties: %{machine: S.machine(), event: S.machine_event()},
           required: [:machine, :event]
         }}
    ]
  )

  def log_machine_event(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with {:ok, %{event: event}} <-
           ManageInventory.log_machine_event(context, id, conn.body_params),
         %{} = machine <-
           Enum.find(Inventory.list_machines(context), &(&1.id == event.machine_id)) ||
             Inventory.get_machine(context, id) do
      conn
      |> put_status(:created)
      |> json(%{machine: redact(machine, context), event: hd(with_nicknames([event]))})
    end
  end

  # ── Consumables ─────────────────────────────────────────────────────────

  operation(:supplies,
    summary: "Consumables with stock and how long it lasts",
    responses: [ok: {"Supplies", "application/json", S.many(:supplies, S.supply())}]
  )

  def supplies(conn, _params) do
    context = conn.assigns.tenant_context
    supplies = context |> Inventory.list_supplies() |> Enum.map(&with_report_people/1)
    json(conn, %{supplies: redact(supplies, context)})
  end

  operation(:supply_reports,
    summary: "Every \"running low\" report on a consumable: who, when, note, resolved",
    parameters: [@id],
    responses: [ok: {"Reports", "application/json", S.many(:reports, S.low_report())}]
  )

  def supply_reports(conn, %{id: id}) do
    reports = Inventory.list_supply_reports(conn.assigns.tenant_context, id)
    json(conn, %{reports: with_people(reports)})
  end

  operation(:report_low,
    summary: "Report a consumable running low or empty, with a note (anyone on the team)",
    parameters: [@id],
    request_body: S.body(S.low_report_body()),
    responses: [
      created:
        {"Reported", "application/json",
         %Schema{
           type: :object,
           properties: %{report: S.low_report(), supply: S.supply()},
           required: [:report, :supply]
         }}
    ]
  )

  def report_low(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with {:ok, %{report: report, supply: supply}} <-
           ManageInventory.report_low(context, id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{
        report: hd(with_people([report])),
        supply: supply |> with_report_people() |> redact(context)
      })
    end
  end

  operation(:create_supply,
    summary: "Add a consumable",
    request_body: S.body(S.supply_body()),
    responses: [created: {"Supply", "application/json", S.one(:supply, S.supply())}]
  )

  def create_supply(conn, _params) do
    with {:ok, supply} <-
           Inventory.save_supply(conn.assigns.tenant_context, nil, conn.body_params) do
      conn |> put_status(:created) |> json(%{supply: supply})
    end
  end

  operation(:update_supply,
    summary: "Edit a consumable (use movements to change the count)",
    parameters: [@id],
    request_body: S.body(S.supply_body()),
    responses: [ok: {"Supply", "application/json", S.one(:supply, S.supply())}]
  )

  def update_supply(conn, %{id: id}) do
    with {:ok, supply} <- Inventory.save_supply(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{supply: supply})
    end
  end

  operation(:archive_supply,
    summary: "Stop tracking a consumable (its history is kept)",
    parameters: [@id],
    responses: [
      ok:
        {"Supply", "application/json",
         S.one(:supply, %Schema{type: :object, additionalProperties: true})}
    ]
  )

  def archive_supply(conn, %{id: id}) do
    with {:ok, supply} <- Inventory.archive_supply(conn.assigns.tenant_context, id) do
      json(conn, %{supply: supply})
    end
  end

  operation(:movements,
    summary: "A consumable's restocks, uses and recounts",
    parameters: [@id],
    responses: [ok: {"Movements", "application/json", S.many(:movements, S.movement())}]
  )

  def movements(conn, %{id: id}) do
    movements = Inventory.list_movements(conn.assigns.tenant_context, id)
    json(conn, %{movements: with_nicknames(movements)})
  end

  operation(:record_movement,
    summary: "Restock, use or recount a consumable",
    parameters: [@id],
    request_body: S.body(S.movement_body()),
    responses: [
      created:
        {"Recorded", "application/json",
         %Schema{
           type: :object,
           properties: %{supply: S.supply(), movement: S.movement()},
           required: [:supply, :movement]
         }}
    ]
  )

  def record_movement(conn, %{id: id}) do
    with {:ok, %{supply: supply, movement: movement}} <-
           ManageInventory.record_movement(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{supply: supply, movement: hd(with_nicknames([movement]))})
    end
  end

  # ── Report ──────────────────────────────────────────────────────────────

  operation(:report,
    summary: "How fast consumables go, what they cost, and monthly inventory expenses",
    parameters: [
      %Parameter{
        name: :months,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 36}
      }
    ],
    responses: [ok: {"Report", "application/json", S.report()}]
  )

  def report(conn, params) do
    json(conn, Inventory.report(conn.assigns.tenant_context, Map.get(params, :months) || 12))
  end

  defp redact(records, context) when is_list(records),
    do: Enum.map(records, &redact(&1, context))

  defp redact(record, context) do
    if Organizations.can?(context, :manage_inventory),
      do: record,
      else: Map.drop(record, @money_fields)
  end

  defp with_report_people(supply),
    do: Map.update(supply, :open_reports, [], &with_people/1)

  # Provenance: who reported (and who resolved) each report.
  defp with_people(reports) do
    nicknames =
      reports
      |> Enum.flat_map(&[&1.user_id, &1.resolved_by_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(reports, fn report ->
      Map.merge(report, %{
        nickname: Map.get(nicknames, report.user_id),
        resolved_by: Map.get(nicknames, report.resolved_by_id)
      })
    end)
  end

  defp with_nicknames(records) do
    nicknames =
      records
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(records, &Map.put(&1, :nickname, Map.get(nicknames, &1.user_id)))
  end
end
