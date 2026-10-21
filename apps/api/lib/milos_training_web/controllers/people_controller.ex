defmodule MilosTrainingWeb.PeopleController do
  @moduledoc "Another person's profile and the posts you may read (ADR-142, P2-M2)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.SocialProfile
  alias MilosTrainingWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

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
end
