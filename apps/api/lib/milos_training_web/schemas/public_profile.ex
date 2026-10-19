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
        :amenities,
        :services,
        :cover,
        :photos,
        :published,
        :published_at,
        :unpublished_changes,
        :missing,
        :lock_version
      ],
      properties: %{
        about: %Schema{type: :string, nullable: true},
        disciplines: %Schema{type: :array, items: discipline()},
        languages: %Schema{type: :array, items: %Schema{type: :string, pattern: "^[a-z]{2}$"}},
        audiences: %Schema{type: :array, items: audience()},
        amenities: %Schema{type: :array, items: amenity()},
        services: %Schema{type: :array, items: service()},
        cover: %Schema{Media.media() | nullable: true},
        photos: %Schema{type: :array, items: Media.media()},
        published: %Schema{type: :boolean},
        unpublished_changes: %Schema{
          type: :boolean,
          description: "The draft differs from what visitors see."
        },
        missing: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["about", "disciplines"]},
          description: "What the draft still needs before it can be published."
        },
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
        amenities: %Schema{type: :array, items: amenity()},
        services: %Schema{type: :array, items: service()},
        cover_photo_id: %Schema{type: :string, format: :uuid, nullable: true},
        photo_ids: %Schema{
          type: :array,
          items: %Schema{type: :string, format: :uuid},
          maxItems: Organizations.box_profile_max_photos(),
          description: "Ready box_photo media of the gallery, in display order."
        },
        lock_version: %Schema{type: :integer, description: "The version the editor read."}
      }
    }
  end

  def publish_request do
    %Schema{
      title: "BoxPublicProfilePublish",
      type: :object,
      properties: %{
        lock_version: %Schema{type: :integer, description: "The version the editor read."}
      }
    }
  end

  def suggestion_request do
    %Schema{
      title: "BoxTagSuggestionRequest",
      type: :object,
      required: [:list, :name],
      properties: %{
        list: %Schema{type: :string, enum: Organizations.box_suggestion_lists()},
        name: %Schema{type: :string, minLength: 2, maxLength: 60}
      }
    }
  end

  def suggestion do
    %Schema{
      title: "BoxTagSuggestion",
      type: :object,
      required: [:id, :list, :name, :status],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        list: %Schema{type: :string},
        name: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["pending", "added", "declined"]},
        organization_name: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  def vocabulary do
    %Schema{
      title: "BoxVocabulary",
      type: :object,
      required: [:discipline_groups, :audiences, :amenities, :services],
      properties: %{
        discipline_groups: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:key, :items],
            properties: %{
              key: %Schema{type: :string},
              items: %Schema{type: :array, items: discipline()}
            }
          }
        },
        audiences: %Schema{type: :array, items: audience()},
        amenities: %Schema{type: :array, items: amenity()},
        services: %Schema{type: :array, items: service()}
      }
    }
  end

  def amenity, do: %Schema{type: :string, enum: Organizations.box_amenities()}
  def service, do: %Schema{type: :string, enum: Organizations.box_services()}
  def discipline, do: %Schema{type: :string, enum: Organizations.box_disciplines()}
  def audience, do: %Schema{type: :string, enum: Organizations.box_audiences()}
end
