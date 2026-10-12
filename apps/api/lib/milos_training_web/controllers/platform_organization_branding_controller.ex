defmodule MilosTrainingWeb.PlatformOrganizationBrandingController do
  @moduledoc "Vendor logo upload for any organization from the platform console (ADR-111)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    FinalizeOrganizationLogo,
    RemoveOrganizationLogo,
    RequestOrganizationLogoUpload
  }

  alias MilosTrainingWeb.AdminBrandingController
  alias MilosTrainingWeb.Schemas.OrganizationBranding
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Platform Organizations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:logo_upload_url, :finalize_logo]

  @organization_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:logo_upload_url,
    summary: "Create a constrained presigned upload for an organization logo",
    parameters: [@organization_id],
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
             conn.assigns.platform_context,
             organization_id(conn),
             conn.body_params
           ) do
      json(conn, upload)
    end
  end

  operation(:finalize_logo,
    summary: "Verify an uploaded logo and make it the organization's logo",
    parameters: [@organization_id],
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
             conn.assigns.platform_context,
             organization_id(conn),
             AdminBrandingController.logo_key(conn.body_params)
           ) do
      json(conn, %{branding: OrganizationBranding.serialize(settings)})
    end
  end

  operation(:remove_logo,
    summary: "Remove an organization's logo",
    parameters: [@organization_id],
    responses: [
      ok: {"Branding", "application/json", OrganizationBranding.branding_response()}
    ]
  )

  def remove_logo(conn, %{"id" => organization_id}) do
    with {:ok, settings} <-
           RemoveOrganizationLogo.call(conn.assigns.platform_context, organization_id) do
      json(conn, %{branding: OrganizationBranding.serialize(settings)})
    end
  end

  # CastAndValidate casts path params into atom keys on conn.params.
  defp organization_id(conn), do: conn.params[:id] || conn.params["id"]
end
