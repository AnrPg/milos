defmodule PaleeWeb.AdminBrandingController do
  @moduledoc "Tenant owner/admin logo upload (ADR-121)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    FinalizeOrganizationLogo,
    GetOrganizationBranding,
    RemoveOrganizationLogo,
    RequestOrganizationLogoUpload
  }

  alias PaleeWeb.Schemas.OrganizationBranding
  alias OpenApiSpex.{MediaType, RequestBody}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:logo_upload_url, :finalize_logo]

  operation(:show,
    summary: "Fetch the organization's branding",
    responses: [
      ok: {"Branding", "application/json", OrganizationBranding.branding_response()}
    ]
  )

  def show(conn, _params) do
    with {:ok, settings} <- GetOrganizationBranding.call(conn.assigns.tenant_context) do
      json(conn, %{branding: OrganizationBranding.serialize(settings)})
    end
  end

  operation(:logo_upload_url,
    summary: "Create a constrained presigned upload for a new organization logo",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: OrganizationBranding.logo_upload_request()}
      }
    },
    responses: [
      ok: {"Upload URL", "application/json", OrganizationBranding.logo_upload()}
    ]
  )

  def logo_upload_url(conn, _params) do
    with {:ok, upload} <-
           RequestOrganizationLogoUpload.call(
             conn.assigns.tenant_context,
             nil,
             conn.body_params
           ) do
      json(conn, upload)
    end
  end

  operation(:finalize_logo,
    summary: "Verify an uploaded logo and make it the organization's logo",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: OrganizationBranding.logo_finalize_request()}
      }
    },
    responses: [
      ok: {"Branding", "application/json", OrganizationBranding.branding_response()}
    ]
  )

  def finalize_logo(conn, _params) do
    with {:ok, settings} <-
           FinalizeOrganizationLogo.call(
             conn.assigns.tenant_context,
             nil,
             logo_key(conn.body_params)
           ) do
      json(conn, %{branding: OrganizationBranding.serialize(settings)})
    end
  end

  operation(:remove_logo,
    summary: "Remove the organization's logo",
    responses: [
      ok: {"Branding", "application/json", OrganizationBranding.branding_response()}
    ]
  )

  def remove_logo(conn, _params) do
    with {:ok, settings} <- RemoveOrganizationLogo.call(conn.assigns.tenant_context) do
      json(conn, %{branding: OrganizationBranding.serialize(settings)})
    end
  end

  @doc false
  def logo_key(%{logo_key: key}), do: key
  def logo_key(%{"logo_key" => key}), do: key
  def logo_key(_params), do: nil
end
