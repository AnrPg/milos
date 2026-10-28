defmodule PaleeWeb.BoxSearchController do
  @moduledoc "ADR-216: find a published box or independent coach by name."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BoxSearch
  alias PaleeWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary:
      "ADR-216: published, live boxes and independent coaches whose name holds the query (accents and case ignored)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: true,
        schema: %Schema{type: :string, minLength: 1, maxLength: 80}
      }
    ],
    responses: [ok: {"Boxes", "application/json", S.box_search_response()}]
  )

  def index(conn, %{q: query}) do
    with {:ok, result} <- BoxSearch.call(conn.assigns.user_context, query),
         do: json(conn, result)
  end
end
