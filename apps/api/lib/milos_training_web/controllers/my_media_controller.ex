defmodule MilosTrainingWeb.MyMediaController do
  @moduledoc """
  Photos and videos for your posts (ADR-157): one presigned upload per file
  as soon as it is picked, then `complete`; the server strips metadata and
  builds renditions in the background while the compose polls `show`.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{CompleteMediaUpload, MyMedia, RequestMediaUpload}
  alias MilosTrainingWeb.Schemas.{Community, Media}
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Media"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @media {"Media", "application/json", Media.media_response()}

  operation(:capabilities,
    summary: "What the compose may offer: photo and video limits on this server",
    responses: [ok: {"Capabilities", "application/json", Media.capabilities()}]
  )

  def capabilities(conn, _params), do: json(conn, MyMedia.capabilities())

  operation(:upload,
    summary: "Reserve an upload for a post photo or video and get a presigned PUT for it",
    request_body: Community.body(Media.post_upload_request()),
    responses: [ok: {"Upload", "application/json", Media.upload()}]
  )

  def upload(conn, _params) do
    params = conn.body_params

    with {:ok, upload} <-
           RequestMediaUpload.call(conn.assigns.user_context, params.purpose, params) do
      json(conn, upload)
    end
  end

  operation(:complete,
    summary: "The upload finished: verify its type and size and start processing it",
    parameters: [@id],
    responses: [ok: @media]
  )

  def complete(conn, %{id: id}) do
    context = conn.assigns.user_context

    with {:ok, %{purpose: purpose}} <- MyMedia.get(context, id),
         {:ok, media} <- CompleteMediaUpload.call(context, purpose, id) do
      json(conn, %{media: media})
    end
  end

  operation(:show,
    summary: "One of your uploads, while it processes and after",
    parameters: [@id],
    responses: [ok: @media]
  )

  def show(conn, %{id: id}) do
    with {:ok, media} <- MyMedia.get(conn.assigns.user_context, id),
         do: json(conn, %{media: media})
  end

  operation(:update,
    summary: "Set or clear an upload's alternative text (its post follows)",
    parameters: [@id],
    request_body: Community.body(Media.alt_text_request()),
    responses: [ok: @media]
  )

  def update(conn, %{id: id}) do
    with {:ok, media} <-
           MyMedia.update_alt_text(conn.assigns.user_context, id, conn.body_params.alt_text) do
      json(conn, %{media: media})
    end
  end

  operation(:delete,
    summary: "Remove an upload you took out of the compose (not one in a post)",
    parameters: [@id],
    responses: [no_content: {"Removed", "application/json", %Schema{type: :object}}]
  )

  def delete(conn, %{id: id}) do
    with :ok <- MyMedia.discard(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:suggest_alt_text,
    summary: "Suggest alternative text for a ready photo (shown to you only, never saved)",
    parameters: [@id],
    request_body: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: Media.alt_text_suggestion_request()}}
    },
    responses: [ok: {"Suggestion", "application/json", Media.alt_text_suggestion_response()}]
  )

  def suggest_alt_text(conn, %{id: id}) do
    params = if is_map(conn.body_params), do: conn.body_params, else: %{}

    with {:ok, suggestion} <- MyMedia.suggest_alt_text(conn.assigns.user_context, id, params) do
      json(conn, suggestion)
    end
  end
end
