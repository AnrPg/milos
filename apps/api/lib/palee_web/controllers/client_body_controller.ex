defmodule PaleeWeb.ClientBodyController do
  @moduledoc """
  A coach reads the body snapshots a client shared (ADR-158): only shared
  snapshots, photos only with the client's consent, the client's display
  choice applied, every read logged where the client can see it.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ClientBody
  alias PaleeWeb.Schemas.Body, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Body"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "A client's shared body snapshots (reads are logged for the client)",
    parameters: [
      @user_id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [ok: {"Snapshots", "application/json", S.snapshot_page()}]
  )

  def index(conn, %{user_id: user_id} = params) do
    with {:ok, page} <- ClientBody.list(conn.assigns.tenant_context, user_id, params),
         do: json(conn, page)
  end

  operation(:series,
    summary: "One metric of a client over a range, as the client's display allows (logged)",
    parameters: [
      @user_id,
      %Parameter{
        name: :metric,
        in: :query,
        required: true,
        schema: %Schema{type: :string, enum: Palee.Body.metric_keys()}
      },
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.Body.ranges()}
      }
    ],
    responses: [ok: {"Series", "application/json", S.series()}]
  )

  def series(conn, %{user_id: user_id} = params) do
    with {:ok, series} <- ClientBody.series(conn.assigns.tenant_context, user_id, params),
         do: json(conn, series)
  end

  operation(:show,
    summary: "One shared snapshot of a client (the read is logged for the client)",
    parameters: [
      @user_id,
      %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
    ],
    responses: [ok: {"Snapshot", "application/json", S.snapshot_response()}]
  )

  def show(conn, %{user_id: user_id, id: id}) do
    with {:ok, snapshot} <- ClientBody.show(conn.assigns.tenant_context, user_id, id),
         do: json(conn, %{snapshot: snapshot})
  end
end
