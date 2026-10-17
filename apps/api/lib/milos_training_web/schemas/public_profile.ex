defmodule MilosTrainingWeb.Schemas.PublicProfile do
  @moduledoc "OpenAPI schemas of a gym's public profile (ADR-142)."

  alias MilosTraining.Organizations
  alias MilosTrainingWeb.Schemas.Media
  alias OpenApiSpex.Schema

  def profile do
    %Schema{
      title: "BoxPublicProfile",
      type: :object,
      required: [
        :about,
        :disciplines,
        :languages,
        :audiences,
        :photos,
        :published,
        :published_at,
        :lock_version
      ],
      properties: %{
        about: %Schema{type: :string, nullable: true},
        disciplines: %Schema{type: :array, items: discipline()},
        languages: %Schema{type: :array, items: %Schema{type: :string, pattern: "^[a-z]{2}$"}},
        audiences: %Schema{type: :array, items: audience()},
        photos: %Schema{type: :array, items: Media.media()},
        published: %Schema{type: :boolean},
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        lock_version: %Schema{type: :integer},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    }
  end

  def profile_response do
    %Schema{
      title: "BoxPublicProfileResponse",
      type: :object,
      required: [:profile],
      properties: %{profile: profile()}
    }
  end

  def update_request do
    %Schema{
      title: "BoxPublicProfileUpdate",
      type: :object,
      properties: %{
        about: %Schema{type: :string, maxLength: 2_000, nullable: true},
        disciplines: %Schema{type: :array, items: discipline()},
        languages: %Schema{type: :array, items: %Schema{type: :string, pattern: "^[a-zA-Z]{2}$"}},
        audiences: %Schema{type: :array, items: audience()},
        photo_ids: %Schema{
          type: :array,
          items: %Schema{type: :string, format: :uuid},
          maxItems: Organizations.box_profile_max_photos(),
          description: "Ready box_photo media, in display order."
        },
        published: %Schema{type: :boolean},
        lock_version: %Schema{type: :integer, description: "The version the editor read."}
      }
    }
  end

  def discipline, do: %Schema{type: :string, enum: Organizations.box_disciplines()}
  def audience, do: %Schema{type: :string, enum: Organizations.box_audiences()}
end
