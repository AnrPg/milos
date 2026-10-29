defmodule PaleeWeb.AdminBoxScreenController do
  @moduledoc """
  Staff › Box screens (ADR-253): the box's TVs, their pairing codes and
  what each one shows (automatic, or pinned by staff).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.BoxScreens.BoxScreenAdmin
  alias PaleeWeb.Schemas.BoxScreens, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Box screens"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "The box's screens (those of the branches the staff member works at)",
    responses: [ok: {"Box screens", "application/json", S.screen_list()}]
  )

  def index(conn, _params), do: json(conn, BoxScreenAdmin.list(conn.assigns.tenant_context))

  operation(:create,
    summary: "Add a box screen and get its pairing code",
    description:
      "The code is shown once and works for 15 minutes; type it on the TV. A box has at " <>
        "most 20 screens. `location_id` null shows the whole box.",
    request_body: S.body(S.create_request()),
    responses: [
      created: {"Box screen and pairing code", "application/json", S.screen_with_code()},
      unprocessable_entity: {"Invalid name or branch", "application/json", S.error()},
      conflict: {"Too many screens", "application/json", S.error()}
    ]
  )

  def create(conn, _params) do
    with {:ok, result} <- BoxScreenAdmin.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:update,
    summary: "Rename a box screen or move it to another branch",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [
      ok: {"Box screen", "application/json", S.screen_response()},
      not_found: {"No such screen", "application/json", S.error()},
      unprocessable_entity: {"Invalid name or branch", "application/json", S.error()}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, result} <-
           BoxScreenAdmin.update(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:delete,
    summary: "Remove a box screen: its TV stops at once",
    parameters: [@id],
    responses: [
      no_content: "Removed",
      not_found: {"No such screen", "application/json", S.error()}
    ]
  )

  def delete(conn, %{id: id}) do
    with :ok <- BoxScreenAdmin.delete(conn.assigns.tenant_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:pairing_code,
    summary: "A new pairing code for a screen (to pair it with another TV)",
    description:
      "Replaces any pending code. The paired TV keeps working until another device pairs " <>
        "with the new code.",
    parameters: [@id],
    responses: [
      created: {"Box screen and pairing code", "application/json", S.screen_with_code()},
      not_found: {"No such screen", "application/json", S.error()}
    ]
  )

  def pairing_code(conn, %{id: id}) do
    with {:ok, result} <- BoxScreenAdmin.pairing_code(conn.assigns.tenant_context, id) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:put_override,
    summary: "Choose what a screen shows and pin it",
    description:
      "`wod`, `timer`, `leaderboard`, `bookings` or one `class` (with `slot_id`, one of " <>
        "today's classes on the screen), optionally until a time. The TV changes at once.",
    parameters: [@id],
    request_body: S.body(S.override_request()),
    responses: [
      ok: {"Box screen", "application/json", S.screen_response()},
      not_found: {"No such screen", "application/json", S.error()},
      unprocessable_entity: {"Invalid choice", "application/json", S.error()}
    ]
  )

  def put_override(conn, %{id: id}) do
    with {:ok, result} <-
           BoxScreenAdmin.put_override(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:delete_override,
    summary: "Return the screen to automatic («Επιστροφή στο αυτόματο»)",
    parameters: [@id],
    responses: [
      ok: {"Box screen", "application/json", S.screen_response()},
      not_found: {"No such screen", "application/json", S.error()}
    ]
  )

  def delete_override(conn, %{id: id}) do
    with {:ok, result} <- BoxScreenAdmin.delete_override(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end
end
