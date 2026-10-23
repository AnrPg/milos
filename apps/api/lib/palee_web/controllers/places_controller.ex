defmodule PaleeWeb.PlacesController do
  @moduledoc "The neighbourhood gazetteer, worldwide place search and «Η περιοχή μου» (ADR-154, ADR-188)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.AroundArea
  alias PaleeWeb.Schemas.Around, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Around"])
  security([%{"bearerAuth" => []}])

  operation(:neighbourhoods,
    summary:
      "Stored places matching a name (case and accents ignored), then places and addresses anywhere from the geocoder (ADR-188)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 100}
      }
    ],
    responses: [ok: {"Places", "application/json", S.neighbourhoods_response()}]
  )

  def neighbourhoods(conn, params) do
    with {:ok, result} <- AroundArea.neighbourhoods(params["q"]), do: json(conn, result)
  end

  operation(:import,
    summary:
      "Store a place a search suggested and get its gazetteer id (an address becomes its neighbourhood)",
    request_body: S.body(S.place_import_request()),
    responses: [
      ok: {"Place", "application/json", S.place_import_response()},
      unprocessable_entity: {"Expired or forged ref", "application/json", S.error()}
    ]
  )

  def import(conn, _params) do
    with {:ok, result} <- AroundArea.import_place(conn.body_params["ref"]), do: json(conn, result)
  end

  operation(:area,
    summary: "Your «Η περιοχή μου»",
    responses: [ok: {"Area", "application/json", S.area_response()}]
  )

  def area(conn, _params) do
    with {:ok, area} <- AroundArea.get(conn.assigns.user_context), do: json(conn, area)
  end

  operation(:update_area,
    summary: "Set «Η περιοχή μου» (up to 5 neighbourhoods; the first is the main one)",
    request_body: S.body(S.area_request()),
    responses: [ok: {"Area", "application/json", S.area_response()}]
  )

  def update_area(conn, _params) do
    with {:ok, area} <-
           AroundArea.put(conn.assigns.user_context, conn.body_params["neighbourhood_ids"]),
         do: json(conn, area)
  end
end
