defmodule PaleeWeb.AdminPublicProfileController do
  @moduledoc "Staff edit the gym's public profile and upload its photos (ADR-142, ADR-148)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    BoxPublicProfile,
    CompleteMediaUpload,
    PublishBoxPublicProfile,
    RequestMediaUpload,
    SuggestBoxTag,
    UpdateBoxPublicProfile
  }

  alias PaleeWeb.Schemas.{Media, PublicProfile}
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update, :publish, :suggest, :photo_upload]

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
    summary: "Edit the draft of the gym's public profile; visitors see it after publishing",
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

  operation(:publish,
    summary: "Publish the draft: visitors see it from now on",
    request_body: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: PublicProfile.publish_request()}}
    },
    responses: [
      ok: {"Profile", "application/json", PublicProfile.profile_response()},
      conflict: {"Edited meanwhile", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Something is missing", "application/json", %Schema{type: :object}}
    ]
  )

  def publish(conn, _params) do
    params = Map.new(conn.body_params || %{}, fn {key, value} -> {to_string(key), value} end)

    with {:ok, profile} <- PublishBoxPublicProfile.publish(conn.assigns.tenant_context, params) do
      json(conn, %{profile: profile})
    end
  end

  operation(:unpublish,
    summary: "Hide the public page; the draft is kept",
    responses: [ok: {"Profile", "application/json", PublicProfile.profile_response()}]
  )

  def unpublish(conn, _params) do
    with {:ok, profile} <- PublishBoxPublicProfile.unpublish(conn.assigns.tenant_context) do
      json(conn, %{profile: profile})
    end
  end

  operation(:suggest,
    summary: "Suggest a tag missing from a list, for review",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: PublicProfile.suggestion_request()}}
    },
    responses: [
      created:
        {"Suggestion", "application/json",
         %Schema{
           type: :object,
           required: [:suggestion],
           properties: %{suggestion: PublicProfile.suggestion()}
         }},
      unprocessable_entity: {"Invalid suggestion", "application/json", %Schema{type: :object}}
    ]
  )

  def suggest(conn, _params) do
    params = Map.new(conn.body_params, fn {key, value} -> {to_string(key), value} end)

    with {:ok, suggestion} <- SuggestBoxTag.call(conn.assigns.tenant_context, params) do
      conn |> put_status(:created) |> json(%{suggestion: suggestion})
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
