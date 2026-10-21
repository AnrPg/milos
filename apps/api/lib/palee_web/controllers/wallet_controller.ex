defmodule PaleeWeb.WalletController do
  @moduledoc """
  Εγώ › Συνδεδεμένες συσκευές and the Wallet card download (ADR-155).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.{ConnectedDevices, WalletPasses}
  alias PaleeWeb.Schemas.CheckIn, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Connected devices"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:devices,
    summary: "My Wallet cards, calendar feed and health integrations",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Connected devices", "application/json", S.devices_response()}]
  )

  def devices(conn, _params) do
    with {:ok, devices} <-
           ConnectedDevices.call(conn.assigns.user_context, GuardianPlug.current_resource(conn)),
         do: json(conn, devices)
  end

  operation(:revoke,
    summary: "Revoke one of my Wallet cards: it stops scanning at once",
    security: [%{"bearerAuth" => []}],
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"The card", "application/json", S.wallet_pass_response()},
      not_found: {"No such card", "application/json", S.error()}
    ]
  )

  def revoke(conn, %{id: id}) do
    with {:ok, pass} <- WalletPasses.revoke(conn.assigns.user_context, id),
         do: json(conn, %{pass: pass})
  end

  operation(:download,
    summary: "The Apple Wallet .pkpass behind a short-lived download link",
    parameters: [
      %Parameter{name: :token, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Pass", "application/vnd.apple.pkpass", %Schema{type: :string, format: :binary}},
      unprocessable_entity: {"Expired link or revoked card", "application/json", S.error()}
    ]
  )

  def download(conn, %{token: token}) do
    with {:ok, %{body: body, filename: filename}} <- WalletPasses.download(token) do
      conn
      |> put_resp_content_type("application/vnd.apple.pkpass", nil)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, body)
    end
  end
end
