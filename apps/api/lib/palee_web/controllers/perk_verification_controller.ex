defmodule PaleeWeb.PerkVerificationController do
  @moduledoc """
  The partner's counter checks a member's perk QR and marks it used, with
  no account (ADR-191 §3). The signed, short-lived, single-use token in the
  path is the credential; the route is rate limited and never cached.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PerkVerification
  alias PaleeWeb.Schemas.Perks, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Perk verification"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @token %Parameter{
    name: :token,
    in: :path,
    required: true,
    schema: %Schema{type: :string, minLength: 16, maxLength: 2048}
  }
  @refused [
    not_found: {"Not a valid link", "application/json", S.error()},
    gone: {"The link expired; ask for the QR again", "application/json", S.error()},
    conflict: {"Already used, or no longer valid", "application/json", S.error()}
  ]

  operation(:show,
    summary: "What a perk QR is for and whether it can still be used",
    parameters: [@token],
    responses: [ok: {"Verification", "application/json", S.verification_response()}] ++ @refused
  )

  def show(conn, %{token: token}) do
    with {:ok, result} <- PerkVerification.inspect_link(token) do
      conn |> no_store() |> json(result)
    end
  end

  operation(:redeem,
    summary: "Mark the perk used (once)",
    parameters: [@token],
    responses: [ok: {"Verification", "application/json", S.verification_response()}] ++ @refused
  )

  def redeem(conn, %{token: token}) do
    with {:ok, result} <- PerkVerification.redeem(token) do
      conn |> no_store() |> json(result)
    end
  end

  defp no_store(conn),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
