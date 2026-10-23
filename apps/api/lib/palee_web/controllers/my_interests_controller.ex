defmodule PaleeWeb.MyInterestsController do
  @moduledoc "«Τι κάνεις»: the current person's disciplines and level (ADR-183)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.MyInterests
  alias PaleeWeb.Schemas.Interests, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Interests"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "Your disciplines and level (empty until you say)",
    responses: [ok: {"Interests", "application/json", S.response()}]
  )

  def show(conn, _params) do
    with {:ok, result} <- MyInterests.get(conn.assigns.user_context), do: json(conn, result)
  end

  operation(:update,
    summary: "Replace your disciplines and level",
    request_body: S.body(S.interests()),
    responses: [ok: {"Interests", "application/json", S.response()}]
  )

  def update(conn, _params) do
    with {:ok, result} <- MyInterests.put(conn.assigns.user_context, conn.body_params),
         do: json(conn, result)
  end
end
