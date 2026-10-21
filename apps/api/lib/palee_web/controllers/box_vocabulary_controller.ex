defmodule PaleeWeb.BoxVocabularyController do
  @moduledoc "The canonical gym tag lists (board 3b): keys only, clients translate them."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BoxPublicProfile
  alias PaleeWeb.Schemas.PublicProfile

  tags(["Public profile"])

  operation(:show,
    summary: "Disciplines by group, audiences, amenities and services",
    responses: [ok: {"Vocabulary", "application/json", PublicProfile.vocabulary()}]
  )

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(BoxPublicProfile.vocabulary())
  end
end
