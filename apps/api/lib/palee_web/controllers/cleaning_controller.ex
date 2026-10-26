defmodule PaleeWeb.CleaningController do
  @moduledoc """
  The cleaning log (ADR-102). Since ADR-202 the areas are the gym's spaces;
  the area endpoints keep their shape. The cleaning schedule and «Σήμερα»
  (what is due today) are ADR-202.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.CleaningLog
  alias Palee.Identity
  alias PaleeWeb.Schemas.Cleaning, as: S
  alias PaleeWeb.Schemas.Spaces, as: SpaceSchemas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Cleaning log"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @space_id %Parameter{name: :space_id, in: :path, required: true, schema: S.uuid()}

  operation(:areas,
    summary: "Cleaning areas (the gym's spaces, ADR-202)",
    responses: [ok: {"Areas", "application/json", S.many(:areas, S.area())}]
  )

  # ADR-186: branch-scoped staff clean and review the areas of their branches.
  def areas(conn, _params) do
    json(conn, %{areas: CleaningLog.areas(conn.assigns.tenant_context)})
  end

  operation(:create_area,
    summary: "Add a cleaning area (a space with tasks)",
    request_body: S.body(S.area_body()),
    responses: [created: {"Area", "application/json", S.one(:area, S.area())}]
  )

  def create_area(conn, _params) do
    with {:ok, area} <- CleaningLog.create_area(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{area: area})
    end
  end

  operation(:update_area,
    summary: "Rename an area or change its tasks",
    parameters: [@id],
    request_body: S.body(S.area_body()),
    responses: [ok: {"Area", "application/json", S.one(:area, S.area())}]
  )

  def update_area(conn, %{id: id}) do
    with {:ok, area} <-
           CleaningLog.update_area(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{area: area})
    end
  end

  operation(:archive_area,
    summary: "Archive an area",
    parameters: [@id],
    responses: [ok: {"Area", "application/json", S.one(:area, S.area())}]
  )

  def archive_area(conn, %{id: id}) do
    with {:ok, area} <- CleaningLog.archive_area(conn.assigns.tenant_context, id) do
      json(conn, %{area: area})
    end
  end

  operation(:entries,
    summary: "The cleaning log: everyone's for reviewers, your own otherwise",
    parameters: [%Parameter{name: :area_id, in: :query, required: false, schema: S.uuid()}],
    responses: [ok: {"Entries", "application/json", S.many(:entries, S.entry())}]
  )

  def entries(conn, params) do
    entries = CleaningLog.entries(conn.assigns.tenant_context, params)
    json(conn, %{entries: with_nicknames(entries)})
  end

  operation(:start,
    summary: "Start cleaning an area",
    request_body:
      S.body(%Schema{type: :object, properties: %{area_id: S.uuid()}, required: [:area_id]}),
    responses: [created: {"Entry", "application/json", S.one(:entry, S.entry())}]
  )

  def start(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, entry} <- CleaningLog.start(context, Map.get(conn.body_params, :area_id)) do
      conn |> put_status(:created) |> json(%{entry: entry})
    end
  end

  operation(:finish,
    summary: "Finish cleaning: the tasks done and an optional note",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{
          tasks_done: %Schema{type: :array, items: %Schema{type: :string}},
          note: %Schema{type: :string, maxLength: 1000, nullable: true}
        }
      }),
    responses: [ok: {"Entry", "application/json", S.one(:entry, S.entry())}]
  )

  def finish(conn, %{id: id}) do
    with {:ok, entry} <- CleaningLog.finish(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{entry: entry})
    end
  end

  operation(:schedules,
    summary: "The cleaning schedule: per space, weekdays, times and a comment",
    responses: [
      ok: {"Schedules", "application/json", S.many(:schedules, SpaceSchemas.schedule())}
    ]
  )

  def schedules(conn, _params) do
    json(conn, %{schedules: CleaningLog.schedules(conn.assigns.tenant_context)})
  end

  operation(:put_schedule,
    summary: "Set when a space is cleaned",
    parameters: [@space_id],
    request_body: S.body(SpaceSchemas.schedule_body()),
    responses: [ok: {"Schedule", "application/json", S.one(:schedule, SpaceSchemas.schedule())}]
  )

  def put_schedule(conn, %{space_id: space_id}) do
    with {:ok, schedule} <-
           CleaningLog.put_schedule(conn.assigns.tenant_context, space_id, conn.body_params) do
      json(conn, %{schedule: schedule})
    end
  end

  operation(:delete_schedule,
    summary: "Take a space off the cleaning schedule",
    parameters: [@space_id],
    responses: [no_content: {"Removed", "application/json", %Schema{type: :object}}]
  )

  def delete_schedule(conn, %{space_id: space_id}) do
    with :ok <- CleaningLog.delete_schedule(conn.assigns.tenant_context, space_id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:today,
    summary: "«Σήμερα»: the spaces due for cleaning today, with their floor plans",
    responses: [
      ok:
        {"Today", "application/json",
         %Schema{
           type: :object,
           properties: %{
             date: %Schema{type: :string, format: :date},
             due: %Schema{type: :array, items: SpaceSchemas.due()},
             open_entries: %Schema{type: :array, items: S.entry()},
             floor_plans: %Schema{type: :array, items: SpaceSchemas.floor_plan()}
           },
           required: [:date, :due, :open_entries, :floor_plans]
         }}
    ]
  )

  def today(conn, _params) do
    json(conn, CleaningLog.today(conn.assigns.tenant_context))
  end

  defp with_nicknames(entries) do
    nicknames =
      entries
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(entries, &Map.put(&1, :nickname, Map.get(nicknames, &1.user_id)))
  end
end
