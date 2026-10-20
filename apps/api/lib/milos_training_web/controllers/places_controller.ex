defmodule MilosTrainingWeb.PlacesController do
  @moduledoc "The neighbourhood gazetteer and «Η περιοχή μου» (ADR-154)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.AroundArea
  alias MilosTrainingWeb.Schemas.Around, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Around"])
  security([%{"bearerAuth" => []}])

  operation(:neighbourhoods,
    summary: "Neighbourhoods and cities matching a name (case and accents ignored)",
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
