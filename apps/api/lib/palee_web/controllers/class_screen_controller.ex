defmodule PaleeWeb.ClassScreenController do
  @moduledoc """
  «Στην οθόνη» on a class timer's remote (ADR-253, update 2026-10-29): the
  class's coach pins its timer, leaderboard or WOD on a box screen and
  returns it to automatic. Only the class's own coach, today, on a screen
  of its branch or the whole box, and staff who manage screens.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.BoxScreens.ClassScreens
  alias PaleeWeb.Schemas.BoxScreens, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Box screens"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slot %Parameter{
    name: :slot_id,
    in: :path,
    required: true,
    description: "Scheduled class ID",
    schema: S.uuid()
  }
  @screen %Parameter{name: :screen_id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "The box screens this class can be shown on, for its coach",
    parameters: [@slot],
    responses: [
      ok: {"Screens of the class", "application/json", S.class_screen_list()},
      forbidden: {"Not this class's coach today", "application/json", S.error()},
      not_found: {"No such class", "application/json", S.error()}
    ]
  )

  def index(conn, %{slot_id: slot_id}) do
    with {:ok, result} <- ClassScreens.list(conn.assigns.tenant_context, slot_id) do
      json(conn, result)
    end
  end

  operation(:put_override,
    summary: "Pin the class's timer, leaderboard or WOD on a box screen",
    description:
      "The class's own coach, today, on a screen of the class's branch or the whole box " <>
        "(or staff who manage screens). The TV changes at once.",
    parameters: [@slot, @screen],
    request_body: S.body(S.class_override_request()),
    responses: [
      ok: {"Box screen", "application/json", S.screen_response()},
      forbidden: {"Not this class's coach today", "application/json", S.error()},
      not_found: {"No such class or screen", "application/json", S.error()},
      unprocessable_entity: {"Invalid choice", "application/json", S.error()}
    ]
  )

  def put_override(conn, %{slot_id: slot_id, screen_id: screen_id}) do
    with {:ok, result} <-
           ClassScreens.pin(conn.assigns.tenant_context, slot_id, screen_id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:delete_override,
    summary: "Return the screen to automatic from the class's remote",
    description: "A coach may only while the screen shows their class, or nothing pinned.",
    parameters: [@slot, @screen],
    responses: [
      ok: {"Box screen", "application/json", S.screen_response()},
      forbidden: {"Not this class's coach, or another choice is pinned", "application/json",
       S.error()},
      not_found: {"No such class or screen", "application/json", S.error()}
    ]
  )

  def delete_override(conn, %{slot_id: slot_id, screen_id: screen_id}) do
    with {:ok, result} <-
           ClassScreens.unpin(conn.assigns.tenant_context, slot_id, screen_id) do
      json(conn, result)
    end
  end
end
