defmodule MilosTrainingWeb.Schemas.Media do
  @moduledoc "OpenAPI schemas of uploaded media (ADR-148)."

  alias MilosTraining.Media
  alias OpenApiSpex.Schema

  def upload_request do
    %Schema{
      title: "MediaUploadRequest",
      type: :object,
      required: [:content_type, :byte_size],
      properties: %{
        content_type: %Schema{
          type: :string,
          enum: Media.content_types(),
          description: "Images are re-encoded in the browser (drops EXIF/GPS) before upload."
        },
        byte_size: %Schema{type: :integer, minimum: 1, maximum: Media.max_bytes()}
      }
    }
  end

  def upload do
    %Schema{
      title: "MediaUpload",
      type: :object,
      required: [:media_id, :upload_url, :required_headers, :expires_in, :max_bytes],
      properties: %{
        media_id: %Schema{type: :string, format: :uuid},
        upload_url: %Schema{type: :string},
        required_headers: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        expires_in: %Schema{type: :integer},
        max_bytes: %Schema{type: :integer}
      }
    }
  end

  def media do
    %Schema{
      title: "Media",
      type: :object,
      required: [:id, :purpose, :status, :content_type, :width, :height, :url],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        purpose: %Schema{type: :string, enum: Media.purposes()},
        status: %Schema{type: :string, enum: ["pending", "ready"]},
        content_type: %Schema{type: :string},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        url: %Schema{
          type: :string,
          nullable: true,
          description: "Stable for public media; presigned and short-lived for private media."
        }
      }
    }
  end

  def media_response do
    %Schema{
      title: "MediaResponse",
      type: :object,
      required: [:media],
      properties: %{media: media()}
    }
  end
end
