defmodule Palee.Application.ManageInventory do
  @moduledoc """
  Inventory changes that alert people (ADR-104): an issue, outage or repair
  call on a machine, and a consumable whose stock drops to low, critical or
  out. Everyone who looks after the inventory (owners, admins, front desk) is
  told, except the person who made the change.
  """

  alias Palee.Application.{MediaUrls, SpaceDirectory}
  alias Palee.{Inventory, Media, Notifications, Organizations, Spaces}

  @max_photos 10

  # Who only reports (coaches, janitors) may add notes, issues and outages;
  # services, repairs, repair calls and retiring stay with who manages.
  @reporter_kinds ["note", "issue", "out_of_order", :note, :issue, :out_of_order]

  def log_machine_event(context, machine_id, params) do
    media_ids = params |> Map.get(:media_ids) |> List.wrap() |> Enum.uniq()

    with :ok <- may_log(context, params[:kind]),
         :ok <- check_photos(context, media_ids),
         {:ok, %{machine: machine, event: event} = result} <-
           Inventory.log_machine_event(
             context,
             machine_id,
             Map.put(params, :media_ids, media_ids)
           ) do
      _ = Media.set_attached(context, :tenant, media_ids, DateTime.utc_now())

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

  # ADR-290: up to 10 ready `machine_photo` uploads on a log line.
  defp check_photos(_context, []), do: :ok

  defp check_photos(_context, ids) when length(ids) > @max_photos,
    do: {:error, :too_many_machine_photos}

  defp check_photos(context, ids) do
    with {:ok, _media} <- Media.fetch_ready(context, "machine_photo", ids), do: :ok
  end

  @doc "Log lines with their photos (`photos: [%{id, url, width, height}]`)."
  def present_events(context, events) do
    ids = events |> Enum.flat_map(&(Map.get(&1, :media_ids) || [])) |> Enum.uniq()

    shown =
      case ids do
        [] ->
          %{}

        ids ->
          context
          |> Media.list(:tenant, ids)
          |> Enum.filter(&(&1.status == "ready" and &1.purpose == "machine_photo"))
          |> Map.new(&{&1.id, MediaUrls.present(context, &1)})
      end

    Enum.map(events, fn event ->
      photos =
        (Map.get(event, :media_ids) || [])
        |> Enum.map(&Map.get(shown, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Map.take(&1, [:id, :url, :width, :height]))

      Map.put(event, :photos, photos)
    end)
  end

  @doc """
  ADR-290: where a machine stands, to draw under its log: each space with
  its floor plan (when it is drawn on one), its area and the machine's pins.
  """
  def places(context, machine) do
    case Inventory.list_placements(context, %{machine_ids: [machine.id]}) do
      [] ->
        []

      placements ->
        spaces =
          context
          |> Spaces.list_spaces(%{
            ids: Enum.map(placements, & &1.space_id),
            include_archived: true
          })
          |> Map.new(&{&1.id, &1})

        plans =
          spaces
          |> Map.values()
          |> Enum.map(& &1.floor_plan_id)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.map(&Spaces.get_floor_plan(context, &1))
          |> Enum.reject(&is_nil/1)
          |> SpaceDirectory.present_plans(context)
          |> Map.new(&{&1.id, &1})

        placements
        |> Enum.filter(&Map.has_key?(spaces, &1.space_id))
        |> Enum.map(fn placement ->
          space = spaces[placement.space_id]
          plan = space.floor_plan_id && plans[space.floor_plan_id]

          %{
            space_id: space.id,
            space_name: space.name,
            quantity: placement.quantity,
            positions: Map.get(placement, :positions) || [],
            area: plan && space.area,
            floor_plan: plan
          }
        end)
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
