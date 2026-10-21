defmodule PaleeWeb.BuddyInviteController do
  @moduledoc """
  The public landing page of a buddy invite link (ADR-160): who invited
  you and whether the link still works. Claiming it needs sign-in
  (`POST /api/me/buddy-invites/:token/claim`).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Buddies
  alias PaleeWeb.Schemas.Buddies, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Buddies"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Preview of a buddy invite link (public)",
    security: [],
    parameters: [
      %Parameter{name: :token, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Preview", "application/json", S.invite_preview()}]
  )

  def show(conn, %{token: token}) do
    with {:ok, preview} <- Buddies.invite_preview(token), do: json(conn, preview)
  end
end
