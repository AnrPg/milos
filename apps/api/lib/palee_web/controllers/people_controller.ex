defmodule PaleeWeb.PeopleController do
  @moduledoc "Another person's profile, the posts you may read and its media grid (ADR-142, ADR-231)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{PeopleSearch, SocialProfile}
  alias PaleeWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:search,
    summary:
      "ADR-193: find people by @handle or name (shared clubs, Buddies, follows, nearby, public)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: true,
        schema: %Schema{type: :string, minLength: 1, maxLength: 80}
      }
    ],
    responses: [ok: {"People", "application/json", S.people_search_response()}]
  )

  def search(conn, %{q: query}) do
    with {:ok, result} <- PeopleSearch.call(conn.assigns.user_context, query),
         do: json(conn, result)
  end

  operation(:show,
    summary: "A person: name, avatar, counts and both follow relationships",
    parameters: [@id],
    responses: [ok: {"Person", "application/json", S.person_response()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, person} <- SocialProfile.person(conn.assigns.user_context, id),
         do: json(conn, person)
  end

  operation(:posts,
    summary: "A person's followers and public posts you may read",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Posts", "application/json", S.person_posts_response()}]
  )

  def posts(conn, %{id: id} = params) do
    with {:ok, page} <- SocialProfile.posts(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end

  operation(:media,
    summary: "ADR-231: the «Πολυμέσα» grid, a person's posts with photos or a video you may read",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Posts", "application/json", S.person_posts_response()}]
  )

  def media(conn, %{id: id} = params) do
    with {:ok, page} <- SocialProfile.media(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end
end
