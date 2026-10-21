defmodule MilosTrainingWeb.AnatomyController do
  @moduledoc """
  The static anatomy taxonomy (ADR-163). It changes only with the code, so
  it is served with a content ETag and a day of private caching; a matching
  `If-None-Match` gets 304.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.GetAnatomyTaxonomy
  alias MilosTrainingWeb.Schemas.WorkoutGoals

  tags(["Anatomy"])
  security([%{"bearerAuth" => []}])

  operation(:taxonomy,
    summary: "The muscle taxonomy and fitness qualities used by WOD goals",
    responses: [
      ok: {"Anatomy taxonomy", "application/json", WorkoutGoals.taxonomy()},
      not_modified: "Unchanged since the given ETag"
    ]
  )

  def taxonomy(conn, _params) do
    {:ok, taxonomy, etag} = GetAnatomyTaxonomy.call()

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "private, max-age=86400")

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, :not_modified, "")
    else
      json(conn, taxonomy)
    end
  end
end
