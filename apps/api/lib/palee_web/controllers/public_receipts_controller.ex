defmodule PaleeWeb.PublicReceiptsController do
  @moduledoc """
  A walk-in's receipt behind the QR on the staff phone (ADR-272): an open,
  signed and expiring link to the receipt's printable page.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.ReceiptLinks

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])

  operation(:show,
    summary: "A walk-in's receipt by its signed link",
    parameters: [
      %Parameter{name: :token, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"The receipt", "text/html", %Schema{type: :string}}
    ]
  )

  def show(conn, %{"token" => token}) do
    with {:ok, %{content: content, content_type: content_type}} <- ReceiptLinks.render(token) do
      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-robots-tag", "noindex")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> send_resp(200, content)
    end
  end
end
