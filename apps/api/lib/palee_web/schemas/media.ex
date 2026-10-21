defmodule PaleeWeb.Schemas.Media do
  @moduledoc "OpenAPI schemas of uploaded media (ADR-148, ADR-157)."

  alias Palee.Media
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
        kind: %Schema{type: :string, enum: ~w(image video)},
        status: %Schema{
          type: :string,
          enum: Media.statuses(),
          description:
            "Post uploads: pending (not uploaded yet) → processing → ready | rejected (see rejection_reason)"
        },
        content_type: %Schema{type: :string},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        url: %Schema{
          type: :string,
          nullable: true,
          description:
            "Stable for public media; presigned and short-lived for private media. A processed upload: its full rendition."
        },
        alt_text: %Schema{type: :string, nullable: true},
        placeholder: %Schema{
          type: :string,
          nullable: true,
          description: "A tiny blurred WebP data URI to show while the image loads"
        },
        duration_ms: %Schema{type: :integer, nullable: true},
        rejection_reason: %Schema{type: :string, nullable: true},
        thumb_url: %Schema{type: :string, nullable: true},
        feed_url: %Schema{type: :string, nullable: true},
        full_url: %Schema{type: :string, nullable: true},
        video_url: %Schema{type: :string, nullable: true}
      }
    }
  end

  @doc "ADR-157: a photo or video in a post, as its readers get it."
  def post_media do
    %Schema{
      title: "PostMedia",
      type: :object,
      description:
        "Renditions are WebP (thumb ~320, feed ~1080, full ~2048 px on the long side); for a video they are its poster and video_url is an H.264/AAC MP4. URLs are short-lived.",
      required: [:id, :kind, :status],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        kind: %Schema{type: :string, enum: ~w(image video)},
        status: %Schema{type: :string, enum: Media.statuses() ++ ["missing"]},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        alt_text: %Schema{type: :string, nullable: true},
        placeholder: %Schema{type: :string, nullable: true},
        duration_ms: %Schema{type: :integer, nullable: true},
        thumb_url: %Schema{type: :string, nullable: true},
        feed_url: %Schema{type: :string, nullable: true},
        full_url: %Schema{type: :string, nullable: true},
        video_url: %Schema{type: :string, nullable: true}
      }
    }
  end

  def post_upload_request do
    %Schema{
      title: "PostMediaUploadRequest",
      type: :object,
      required: [:purpose, :content_type, :byte_size],
      properties: %{
        purpose: %Schema{type: :string, enum: Media.post_purposes()},
        content_type: %Schema{
          type: :string,
          enum: Media.post_content_types(),
          description:
            "Photos and videos go as picked; the server strips their metadata (EXIF, GPS) and re-encodes them."
        },
        byte_size: %Schema{type: :integer, minimum: 1}
      }
    }
  end

  def alt_text_request do
    %Schema{
      title: "MediaAltTextRequest",
      type: :object,
      required: [:alt_text],
      properties: %{
        alt_text: %Schema{type: :string, nullable: true, maxLength: 500}
      }
    }
  end

  def alt_text_suggestion_request do
    %Schema{
      title: "MediaAltTextSuggestionRequest",
      type: :object,
      properties: %{
        locale: %Schema{
          type: :string,
          description: "Language of the suggestion; defaults to yours, then Greek"
        }
      }
    }
  end

  def alt_text_suggestion_response do
    %Schema{
      title: "MediaAltTextSuggestion",
      type: :object,
      required: [:suggestion],
      properties: %{
        suggestion: %Schema{
          type: :string,
          description: "Shown to you only; nothing is saved until you save the alt text"
        }
      }
    }
  end

  def capabilities do
    %Schema{
      title: "PostMediaCapabilities",
      type: :object,
      required: [
        :max_photos,
        :max_videos,
        :video,
        :max_video_seconds,
        :photo_content_types,
        :video_content_types,
        :max_photo_bytes,
        :max_video_bytes,
        :max_alt_text
      ],
      properties: %{
        max_photos: %Schema{type: :integer},
        max_videos: %Schema{type: :integer},
        video: %Schema{type: :boolean, description: "Whether this server can take videos"},
        max_video_seconds: %Schema{type: :integer},
        photo_content_types: %Schema{type: :array, items: %Schema{type: :string}},
        video_content_types: %Schema{type: :array, items: %Schema{type: :string}},
        max_photo_bytes: %Schema{type: :integer},
        max_video_bytes: %Schema{type: :integer},
        max_alt_text: %Schema{type: :integer}
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
