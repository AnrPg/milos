defmodule MilosTrainingWeb.Schemas.OrganizationBranding do
  @moduledoc "OpenAPI schemas and serialization for tenant logo upload (ADR-103)."

  alias OpenApiSpex.Schema

  @max_bytes 2_097_152

  def logo_upload_request do
    %Schema{
      title: "OrganizationLogoUploadRequest",
      type: :object,
      required: [:content_type, :byte_size],
      properties: %{
        content_type: %Schema{type: :string, enum: ["image/png", "image/jpeg", "image/webp"]},
        byte_size: %Schema{type: :integer, minimum: 1, maximum: @max_bytes}
      }
    }
  end

  def logo_upload do
    %Schema{
      title: "OrganizationLogoUpload",
      type: :object,
      required: [:upload_url, :key, :required_headers, :expires_in, :max_bytes],
      properties: %{
        upload_url: %Schema{type: :string},
        key: %Schema{type: :string},
        required_headers: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string}
        },
        expires_in: %Schema{type: :integer},
        max_bytes: %Schema{type: :integer}
      }
    }
  end

  def logo_finalize_request do
    %Schema{
      title: "OrganizationLogoFinalizeRequest",
      type: :object,
      required: [:logo_key],
      properties: %{logo_key: %Schema{type: :string, minLength: 1, maxLength: 255}}
    }
  end

  def branding do
    %Schema{
      title: "OrganizationBranding",
      type: :object,
      required: [:organization_id, :brand_logo_url, :brand_logo_uploaded],
      properties: %{
        organization_id: %Schema{type: :string, format: :uuid},
        brand_name: %Schema{type: :string, nullable: true},
        brand_logo_url: %Schema{type: :string, nullable: true},
        brand_logo_uploaded: %Schema{
          type: :boolean,
          description:
            "True when brand_logo_url is derived from an uploaded logo object (ADR-103)."
        },
        brand_primary_color: %Schema{type: :string, nullable: true}
      }
    }
  end

  def branding_response do
    %Schema{
      title: "OrganizationBrandingResponse",
      type: :object,
      required: [:branding],
      properties: %{branding: branding()}
    }
  end

  def serialize(settings) do
    %{
      organization_id: settings.organization_id,
      brand_name: settings.brand_name,
      brand_logo_url: settings.brand_logo_url,
      brand_logo_uploaded: not is_nil(settings.brand_logo_object_key),
      brand_primary_color: settings.brand_primary_color
    }
  end
end
