defmodule PaleeWeb.AdminContentController do
  @moduledoc "Admin management of on-demand video items (ADR-098)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Content
  alias PaleeWeb.Schemas.Content, as: ContentSchemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Content"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @video_response %Schema{
    type: :object,
    properties: %{video: ContentSchemas.video_schema()},
    required: [:video]
  }
  @error %Schema{type: :object, additionalProperties: true}
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: ContentSchemas.video_params_schema()}}
  }

  operation(:index,
    summary: "List on-demand videos, including drafts and archived ones",
    responses: [
      ok:
        {"Videos", "application/json",
         %Schema{
           type: :object,
           properties: %{videos: %Schema{type: :array, items: ContentSchemas.video_schema()}},
           required: [:videos]
         }}
    ]
  )

  def index(conn, _params) do
    json(conn, %{videos: Content.list_videos(conn.assigns.tenant_context)})
  end

  operation(:create,
    summary: "Add an on-demand video (draft until published)",
    request_body: @body,
    responses: [
      created: {"Video", "application/json", @video_response},
      unprocessable_entity: {"Invalid video", "application/json", @error}
    ]
  )

  def create(conn, _params) do
    admin = GuardianPlug.current_resource(conn)
    params = Map.put(conn.body_params, :created_by_id, admin.id)

    with {:ok, video} <- Content.create_video(conn.assigns.tenant_context, params) do
      conn |> put_status(:created) |> json(%{video: video})
    end
  end

  operation(:update,
    summary: "Edit an on-demand video",
    parameters: [@id],
    request_body: @body,
    responses: [
      ok: {"Video", "application/json", @video_response},
      not_found: {"Not found", "application/json", @error},
      unprocessable_entity: {"Invalid video", "application/json", @error}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, video} <- Content.update_video(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{video: video})
    end
  end

  operation(:publish,
    summary: "Publish or unpublish an on-demand video",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{published: %Schema{type: :boolean}},
            required: [:published]
          }
        }
      }
    },
    responses: [
      ok: {"Video", "application/json", @video_response},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def publish(conn, %{id: id}) do
    published? = Map.get(conn.body_params, :published) == true

    with {:ok, video} <- Content.set_video_published(conn.assigns.tenant_context, id, published?) do
      json(conn, %{video: video})
    end
  end

  operation(:archive,
    summary: "Archive an on-demand video; members no longer see it",
    parameters: [@id],
    responses: [
      ok: {"Video", "application/json", @video_response},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def archive(conn, %{id: id}) do
    with {:ok, video} <- Content.archive_video(conn.assigns.tenant_context, id) do
      json(conn, %{video: video})
    end
  end
end
