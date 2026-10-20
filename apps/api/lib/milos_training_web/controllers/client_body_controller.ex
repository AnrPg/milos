defmodule MilosTrainingWeb.ClientBodyController do
  @moduledoc """
  A coach reads the body snapshots a client shared (ADR-158): only shared
  snapshots, photos only with the client's consent, the client's display
  choice applied, every read logged where the client can see it.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ClientBody
  alias MilosTrainingWeb.Schemas.Body, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

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
