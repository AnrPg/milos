defmodule MilosTrainingWeb.PublicBoxController do
  @moduledoc """
  The box page (ADR-142, P2-M2). Its «Σχετικά» (`show`) is readable without
  an account; its schedule and posts need a signed-in member (board 4 D2).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.PublicBox
  alias MilosTrainingWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Public box page"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The gym's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }

  operation(:show,
    summary: "A published box: who it is, its «Σχετικά» and its locations",
    parameters: [@slug],
    responses: [
      ok: {"Box", "application/json", S.box_response()},
      not_found: {"No published box with this slug", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{slug: slug}) do
    with {:ok, box} <- PublicBox.get(slug), do: json(conn, box)
  end

  operation(:schedule,
    summary: "A published box's classes in a window (read-only; signed in)",
    parameters: [
      @slug,
      %Parameter{name: :start_at, in: :query, required: false, schema: S.datetime()},
      %Parameter{name: :end_at, in: :query, required: false, schema: S.datetime()}
    ],
    responses: [ok: {"Classes", "application/json", S.schedule_response()}]
  )

  def schedule(conn, %{slug: slug} = params) do
    viewer_id = conn.assigns.user_context.user_id

    with {:ok, schedule} <- PublicBox.schedule(slug, viewer_id, params),
         do: json(conn, schedule)
  end

  operation(:posts,
    summary: "Posts a published box made public, newest first (signed in)",
    parameters: [
      @slug,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Posts", "application/json", S.posts_response()}]
  )

  def posts(conn, %{slug: slug} = params) do
    with {:ok, page} <- PublicBox.posts(slug, conn.assigns.user_context.user_id, params),
         do: json(conn, page)
  end
end
