defmodule MilosTrainingWeb.AdminPublicProfileController do
  @moduledoc "Staff edit the gym's public profile and upload its photos (ADR-142, ADR-148)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    BoxPublicProfile,
    CompleteMediaUpload,
    RequestMediaUpload,
    UpdateBoxPublicProfile
  }

  alias MilosTrainingWeb.Schemas.{Media, PublicProfile}
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update, :photo_upload]

  operation(:show,
    summary: "The gym's public profile (Σχετικά of the public box page)",
    responses: [ok: {"Profile", "application/json", PublicProfile.profile_response()}]
  )

  def show(conn, _params) do
    with {:ok, profile} <- BoxPublicProfile.get(conn.assigns.tenant_context) do
      json(conn, %{profile: profile})
    end
  end

  operation(:update,
    summary: "Edit, publish or unpublish the gym's public profile",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: PublicProfile.update_request()}}
    },
    responses: [
      ok: {"Profile", "application/json", PublicProfile.profile_response()},
      conflict: {"Edited meanwhile", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid profile", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, _params) do
    with {:ok, profile} <-
           UpdateBoxPublicProfile.call(conn.assigns.tenant_context, conn.body_params) do
      json(conn, %{profile: profile})
    end
  end

  operation(:photo_upload,
    summary: "Reserve a box photo and get a presigned upload for it",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Media.upload_request()}}
    },
    responses: [ok: {"Upload", "application/json", Media.upload()}]
  )

  def photo_upload(conn, _params) do
    with {:ok, upload} <-
           RequestMediaUpload.call(conn.assigns.tenant_context, "box_photo", conn.body_params) do
      json(conn, upload)
    end
  end

  operation(:complete_photo,
    summary: "Verify an uploaded box photo (type, size, no metadata) and mark it ready",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Media", "application/json", Media.media_response()}]
  )

  def complete_photo(conn, %{"id" => id}) do
    with {:ok, media} <- CompleteMediaUpload.call(conn.assigns.tenant_context, "box_photo", id) do
      json(conn, %{media: media})
    end
  end
end
