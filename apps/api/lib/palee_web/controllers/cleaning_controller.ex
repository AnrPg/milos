defmodule PaleeWeb.CleaningController do
  @moduledoc "The cleaning log (ADR-102)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.{Housekeeping, Identity, Organizations}
  alias PaleeWeb.Schemas.Cleaning, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Cleaning log"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:areas,
    summary: "Cleaning areas",
    responses: [ok: {"Areas", "application/json", S.many(:areas, S.area())}]
  )

  def areas(conn, _params),
    do: json(conn, %{areas: Housekeeping.list_areas(conn.assigns.tenant_context)})

  operation(:create_area,
    summary: "Add a cleaning area",
    request_body: S.body(S.area_body()),
    responses: [created: {"Area", "application/json", S.one(:area, S.area())}]
  )

  def create_area(conn, _params) do
    with {:ok, area} <- Housekeeping.save_area(conn.assigns.tenant_context, nil, conn.body_params) do
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
    with {:ok, area} <- Housekeeping.save_area(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{area: area})
    end
  end

  operation(:archive_area,
    summary: "Archive an area",
    parameters: [@id],
    responses: [ok: {"Area", "application/json", S.one(:area, S.area())}]
  )

  def archive_area(conn, %{id: id}) do
    with {:ok, area} <- Housekeeping.archive_area(conn.assigns.tenant_context, id) do
      json(conn, %{area: area})
    end
  end

  operation(:entries,
    summary: "The cleaning log: everyone's for reviewers, your own otherwise",
    parameters: [%Parameter{name: :area_id, in: :query, required: false, schema: S.uuid()}],
    responses: [ok: {"Entries", "application/json", S.many(:entries, S.entry())}]
  )

  def entries(conn, params) do
    context = conn.assigns.tenant_context

    filters =
      %{area_id: Map.get(params, :area_id)}
      |> then(fn filters ->
        if Organizations.can?(context, :review_cleaning),
          do: filters,
          else: Map.put(filters, :user_id, context.user_id)
      end)

    json(conn, %{entries: context |> Housekeeping.list_entries(filters) |> with_nicknames()})
  end

  operation(:start,
    summary: "Start cleaning an area",
    request_body:
      S.body(%Schema{type: :object, properties: %{area_id: S.uuid()}, required: [:area_id]}),
    responses: [created: {"Entry", "application/json", S.one(:entry, S.entry())}]
  )

  def start(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, entry} <-
           Housekeeping.start(context, context.user_id, Map.get(conn.body_params, :area_id)) do
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
    context = conn.assigns.tenant_context

    with {:ok, entry} <- Housekeeping.finish(context, context.user_id, id, conn.body_params) do
      json(conn, %{entry: entry})
    end
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
