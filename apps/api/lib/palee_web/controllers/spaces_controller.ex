defmodule PaleeWeb.SpacesController do
  @moduledoc "Settings › Spaces: the rooms of each branch and their floor plans (ADR-202)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{CompleteMediaUpload, RequestMediaUpload, SpaceDirectory}
  alias PaleeWeb.Schemas.Cleaning, as: C
  alias PaleeWeb.Schemas.Spaces, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Spaces"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: C.uuid()}

  operation(:index,
    summary: "Spaces and floor plans of the branches the caller works at",
    parameters: [
      %Parameter{name: :location_id, in: :query, required: false, schema: C.uuid()},
      %Parameter{
        name: :include_archived,
        in: :query,
        required: false,
        schema: %Schema{type: :boolean}
      }
    ],
    responses: [
      ok:
        {"Spaces", "application/json",
         %Schema{
           type: :object,
           properties: %{
             spaces: %Schema{type: :array, items: S.space()},
             floor_plans: %Schema{type: :array, items: S.floor_plan()}
           },
           required: [:spaces, :floor_plans]
         }}
    ]
  )

  def index(conn, params) do
    filters =
      params
      |> Map.take([:location_id, :include_archived])
      |> Map.new()

    json(conn, SpaceDirectory.list(conn.assigns.tenant_context, filters))
  end

  operation(:show,
    summary: "A space with its unavailability, upcoming classes and machines",
    parameters: [@id],
    responses: [ok: {"Space", "application/json", C.one(:space, S.space_detail())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, space} <- SpaceDirectory.show(conn.assigns.tenant_context, id) do
      json(conn, %{space: space})
    end
  end

  operation(:create,
    summary: "Add a space",
    request_body: C.body(S.space_body()),
    responses: [created: {"Space", "application/json", C.one(:space, S.space())}]
  )

  def create(conn, _params) do
    with {:ok, space} <- SpaceDirectory.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{space: Map.put(space, :unavailability, [])})
    end
  end

  operation(:update,
    summary: "Change a space (front desk: name, description and directions only)",
    parameters: [@id],
    request_body: C.body(S.space_body()),
    responses: [ok: {"Space", "application/json", C.one(:space, S.space())}]
  )

  def update(conn, %{id: id}) do
    with {:ok, space} <-
           SpaceDirectory.update(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{space: space})
    end
  end

  operation(:archive,
    summary: "Archive a space (its history and cleaning log are kept)",
    parameters: [@id],
    responses: [ok: {"Space", "application/json", C.one(:space, S.space())}]
  )

  def archive(conn, %{id: id}) do
    with {:ok, space} <- SpaceDirectory.archive(conn.assigns.tenant_context, id) do
      json(conn, %{space: space})
    end
  end

  operation(:restore,
    summary: "Bring an archived space back",
    parameters: [@id],
    responses: [ok: {"Space", "application/json", C.one(:space, S.space())}]
  )

  def restore(conn, %{id: id}) do
    with {:ok, space} <- SpaceDirectory.restore(conn.assigns.tenant_context, id) do
      json(conn, %{space: space})
    end
  end

  operation(:make_unavailable,
    summary: "Make a space unavailable from–to, with a reason",
    description:
      "Classes cannot be planned in the space while it is unavailable (`space_unavailable`). " <>
        "Classes already planned then keep their space and are returned as affected_classes.",
    parameters: [@id],
    request_body: C.body(S.unavailability_body()),
    responses: [
      created:
        {"Unavailability", "application/json",
         %Schema{
           type: :object,
           properties: %{
             unavailability: S.unavailability(),
             affected_classes: %Schema{type: :array, items: S.space_class()}
           },
           required: [:unavailability, :affected_classes]
         }}
    ]
  )

  def make_unavailable(conn, %{id: id}) do
    with {:ok, result} <-
           SpaceDirectory.make_unavailable(conn.assigns.tenant_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:delete_unavailability,
    summary: "Remove an unavailability window",
    parameters: [
      @id,
      %Parameter{name: :window_id, in: :path, required: true, schema: C.uuid()}
    ],
    responses: [
      ok: {"Unavailability", "application/json", C.one(:unavailability, S.unavailability())}
    ]
  )

  def delete_unavailability(conn, %{id: id, window_id: window_id}) do
    with {:ok, window} <-
           SpaceDirectory.delete_unavailability(conn.assigns.tenant_context, id, window_id) do
      json(conn, %{unavailability: window})
    end
  end

  # ── Floor plans ─────────────────────────────────────────────────────────

  operation(:floor_plan_upload,
    summary: "Reserve a floor plan image (floor_plan) and get a presigned upload for it",
    request_body: C.body(PaleeWeb.Schemas.Media.upload_request()),
    responses: [ok: {"Upload", "application/json", PaleeWeb.Schemas.Media.upload()}]
  )

  def floor_plan_upload(conn, _params) do
    with {:ok, upload} <-
           RequestMediaUpload.call(conn.assigns.tenant_context, "floor_plan", conn.body_params) do
      json(conn, upload)
    end
  end

  operation(:complete_floor_plan_upload,
    summary: "Verify an uploaded floor plan image and mark it ready",
    parameters: [@id],
    responses: [ok: {"Media", "application/json", PaleeWeb.Schemas.Media.media_response()}]
  )

  def complete_floor_plan_upload(conn, %{id: id}) do
    with {:ok, media} <- CompleteMediaUpload.call(conn.assigns.tenant_context, "floor_plan", id) do
      json(conn, %{media: media})
    end
  end

  operation(:create_floor_plan,
    summary: "Add a floor plan (one floor of a branch) from a ready upload",
    request_body: C.body(S.floor_plan_body()),
    responses: [created: {"Floor plan", "application/json", C.one(:floor_plan, S.floor_plan())}]
  )

  def create_floor_plan(conn, _params) do
    with {:ok, plan} <-
           SpaceDirectory.create_floor_plan(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{floor_plan: plan})
    end
  end

  operation(:update_floor_plan,
    summary: "Rename, reorder or replace the image of a floor plan",
    parameters: [@id],
    request_body: C.body(S.floor_plan_body()),
    responses: [ok: {"Floor plan", "application/json", C.one(:floor_plan, S.floor_plan())}]
  )

  def update_floor_plan(conn, %{id: id}) do
    body = Map.drop(conn.body_params, [:location_id])

    with {:ok, plan} <- SpaceDirectory.update_floor_plan(conn.assigns.tenant_context, id, body) do
      json(conn, %{floor_plan: plan})
    end
  end

  operation(:delete_floor_plan,
    summary: "Remove a floor plan; the spaces drawn on it lose their area",
    parameters: [@id],
    responses: [ok: {"Floor plan", "application/json", C.one(:floor_plan, S.floor_plan())}]
  )

  def delete_floor_plan(conn, %{id: id}) do
    with {:ok, plan} <- SpaceDirectory.delete_floor_plan(conn.assigns.tenant_context, id) do
      json(conn, %{floor_plan: plan})
    end
  end
end
