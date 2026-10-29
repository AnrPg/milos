defmodule PaleeWeb.Schemas.Social do
  @moduledoc "OpenAPI schemas for the public box page, follows and profile posts (ADR-142)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @strings %Schema{type: :array, items: %Schema{type: :string}}

  def uuid, do: @uuid
  def datetime, do: @datetime
  def body(schema), do: Community.body(schema)

  # Public box page ------------------------------------------------------------

  def box do
    %Schema{
      title: "PublicBox",
      type: :object,
      properties: %{
        organization_id: @uuid,
        slug: %Schema{type: :string, description: "Canonical slug; redirect when it differs"},
        name: %Schema{type: :string},
        logo_url: %Schema{type: :string, nullable: true},
        primary_color: %Schema{type: :string, nullable: true}
      },
      required: [:organization_id, :slug, :name]
    }
  end

  defp photo do
    %Schema{
      title: "PublicBoxPhoto",
      type: :object,
      properties: %{
        id: @uuid,
        url: %Schema{type: :string},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :url]
    }
  end

  defp profile do
    %Schema{
      title: "PublicBoxProfile",
      type: :object,
      description: "The published snapshot only; never the draft",
      properties: %{
        about: %Schema{type: :string, nullable: true},
        disciplines: @strings,
        audiences: @strings,
        amenities: @strings,
        services: @strings,
        languages: @strings,
        cover: %Schema{allOf: [photo()], nullable: true},
        photos: %Schema{type: :array, items: photo()},
        coaches: %Schema{type: :array, items: coach()}
      },
      required: [:disciplines, :audiences, :amenities, :services, :languages, :photos, :coaches]
    }
  end

  defp coach do
    %Schema{
      title: "PublicBoxCoach",
      type: :object,
      description: "A coach the owner shows, with what they teach in the coming weeks",
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        class_types: @strings
      },
      required: [:id, :class_types]
    }
  end

  defp location do
    %Schema{
      title: "PublicBoxLocation",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        address: %Schema{type: :string, nullable: true},
        neighbourhood: %Schema{type: :string, nullable: true},
        city: %Schema{type: :string, nullable: true},
        country_code: %Schema{type: :string, nullable: true},
        latitude: %Schema{type: :number, nullable: true},
        longitude: %Schema{type: :number, nullable: true},
        opening_hours: %Schema{
          type: :array,
          items: %Schema{type: :object, additionalProperties: true},
          nullable: true,
          description: "Weekly spans: weekday (1 = Monday), opens, closes"
        },
        accessibility: %Schema{type: :array, items: %Schema{type: :string}, nullable: true}
      },
      required: [:id, :name]
    }
  end

  def box_response do
    %Schema{
      title: "PublicBoxResponse",
      type: :object,
      properties: %{
        box: box(),
        profile: profile(),
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        followers_count: %Schema{type: :integer},
        time_zone: %Schema{
          type: :string,
          description: "ADR-179: the gym's IANA zone; its classes show on this clock"
        },
        locations: %Schema{type: :array, items: location()},
        open_clubs: %Schema{
          type: :array,
          description: "The box's open clubs (ADR-143, board 7 Q6)",
          items: PaleeWeb.Schemas.CommunityGroups.open_club()
        }
      },
      required: [:box, :profile, :followers_count, :locations, :open_clubs]
    }
  end

  def schedule_response do
    slot = %Schema{
      title: "PublicBoxClass",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        scheduled_at: @datetime,
        duration_minutes: %Schema{type: :integer, nullable: true},
        capacity: %Schema{type: :integer, nullable: true},
        spots_remaining: %Schema{type: :integer, nullable: true},
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        trial_seats: %Schema{
          type: :integer,
          nullable: true,
          description: "Trial seats left (ADR-144); null when the class takes no trials"
        },
        coach: %Schema{allOf: [person_ref()], nullable: true},
        class_type: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            name: %Schema{type: :string},
            level: %Schema{type: :string, nullable: true},
            audiences: @strings
          },
          required: [:id, :name, :audiences]
        }
      },
      required: [:id, :name, :scheduled_at]
    }

    %Schema{
      title: "PublicBoxScheduleResponse",
      type: :object,
      properties: %{
        box: box(),
        start_at: @datetime,
        end_at: @datetime,
        time_zone: %Schema{
          type: :string,
          description: "ADR-179: the gym's IANA zone; the classes show on this clock"
        },
        trial_offer: PaleeWeb.Schemas.Trials.offer(),
        slots: %Schema{type: :array, items: slot}
      },
      required: [:box, :start_at, :end_at, :time_zone, :slots]
    }
  end

  def posts_response do
    %Schema{
      title: "PublicBoxPostsResponse",
      type: :object,
      properties: %{
        box: box(),
        posts: %Schema{type: :array, items: Community.post()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:box, :posts]
    }
  end

  # Follows ---------------------------------------------------------------------

  defp target_type, do: %Schema{type: :string, enum: ~w(user organization club)}

  def status, do: %Schema{type: :string, enum: ~w(none requested active)}

  def follow_request do
    %Schema{
      title: "FollowRequest",
      type: :object,
      properties: %{target_type: target_type(), target_id: @uuid},
      required: [:target_type, :target_id]
    }
  end

  def follow_status_response do
    %Schema{
      title: "FollowStatusResponse",
      type: :object,
      properties: %{status: status()},
      required: [:status]
    }
  end

  defp person_ref do
    %Schema{
      title: "PersonRef",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      },
      required: [:id]
    }
  end

  def people_page do
    person = %Schema{
      title: "FollowPerson",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        my_status: %Schema{allOf: [status()], description: "Whether you follow them"},
        buddy: %Schema{type: :boolean, description: "ADR-193: you follow each other"}
      },
      required: [:id, :my_status, :buddy]
    }

    entry = %Schema{
      title: "FollowEntry",
      type: :object,
      properties: %{
        follow_id: @uuid,
        status: status(),
        since: @datetime,
        person: %Schema{allOf: [person], nullable: true},
        box: %Schema{allOf: [box()], nullable: true}
      },
      required: [:follow_id, :status, :since]
    }

    %Schema{
      title: "FollowPage",
      type: :object,
      properties: %{
        entries: %Schema{type: :array, items: entry},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:entries]
    }
  end

  def summary_response do
    %Schema{
      title: "SocialSummary",
      type: :object,
      properties: %{
        posts_count: %Schema{type: :integer},
        media_count: %Schema{
          type: :integer,
          description: "ADR-231: your posts with photos or a video"
        },
        followers_count: %Schema{type: :integer},
        following_count: %Schema{type: :integer},
        requests_count: %Schema{type: :integer},
        booking_sharing: booking_sharing(),
        member_visibility: member_visibility(),
        around_visibility: PaleeWeb.Schemas.Around.around_visibility(),
        privacy: privacy(),
        follow_groups: follow_groups()
      },
      required: [
        :around_visibility,
        :booking_sharing,
        :follow_groups,
        :followers_count,
        :following_count,
        :media_count,
        :member_visibility,
        :posts_count,
        :privacy,
        :requests_count
      ]
    }
  end

  def follow_groups do
    %Schema{
      title: "FollowGroups",
      type: :object,
      description:
        "ADR-193: the person's follows of people in three groups that never overlap: Buddies (both ways), people who follow them only, people they follow only",
      properties: %{
        buddies: %Schema{type: :integer},
        followers_only: %Schema{type: :integer},
        following_only: %Schema{type: :integer}
      },
      required: [:buddies, :followers_only, :following_only]
    }
  end

  def privacy do
    %Schema{
      title: "SocialPrivacy",
      type: :object,
      description:
        "ADR-193: a private account answers follow requests; searchable shows you in people search",
      properties: %{
        private_account: %Schema{type: :boolean},
        searchable: %Schema{type: :boolean}
      },
      required: [:private_account, :searchable]
    }
  end

  def privacy_request do
    %Schema{
      title: "SocialPrivacyRequest",
      type: :object,
      properties: %{
        private_account: %Schema{type: :boolean},
        searchable: %Schema{type: :boolean}
      }
    }
  end

  def people_search_response do
    person = %Schema{
      title: "PeopleSearchPerson",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        relation: %Schema{type: :string, enum: ~w(club buddy follow nearby public)},
        my_status: status(),
        buddy: %Schema{type: :boolean}
      },
      required: [:buddy, :id, :my_status, :relation]
    }

    %Schema{
      title: "PeopleSearchResponse",
      type: :object,
      properties: %{people: %Schema{type: :array, items: person}},
      required: [:people]
    }
  end

  def box_search_response do
    box = %Schema{
      title: "BoxSearchResult",
      type: :object,
      description: "ADR-221: a published, live box or independent coach found by name",
      properties: %{
        organization_id: @uuid,
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        logo_url: %Schema{type: :string, nullable: true},
        primary_color: %Schema{type: :string, nullable: true},
        provider_kind: %Schema{type: :string, enum: ~w(gym coach)},
        neighbourhood: %Schema{type: :string, nullable: true},
        city: %Schema{type: :string, nullable: true},
        my_status: status()
      },
      required: [:my_status, :name, :organization_id, :provider_kind, :slug]
    }

    %Schema{
      title: "BoxSearchResponse",
      type: :object,
      properties: %{boxes: %Schema{type: :array, items: box}},
      required: [:boxes]
    }
  end

  def booking_sharing do
    %Schema{
      title: "BookingSharing",
      type: :object,
      description:
        "Whether followers see the classes you book, and whether the one-time offer was answered",
      properties: %{enabled: %Schema{type: :boolean}, offered: %Schema{type: :boolean}},
      required: [:enabled, :offered]
    }
  end

  def member_visibility do
    %Schema{
      title: "MemberVisibility",
      type: :object,
      description: "Whether you keep out of your clubs' «Μέλη» lists",
      properties: %{hidden: %Schema{type: :boolean}},
      required: [:hidden]
    }
  end

  def booking_sharing_request do
    %Schema{
      title: "BookingSharingRequest",
      type: :object,
      properties: %{enabled: %Schema{type: :boolean}},
      required: [:enabled]
    }
  end

  def person_response do
    %Schema{
      title: "PersonProfile",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        is_me: %Schema{type: :boolean},
        private: %Schema{type: :boolean, description: "ADR-193: following them is a request"},
        followers_count: %Schema{type: :integer},
        following_count: %Schema{type: :integer},
        follow_groups: follow_groups(),
        my_status: status(),
        follows_me: %Schema{type: :boolean},
        buddy: %Schema{type: :boolean, description: "ADR-193: you follow each other"}
      },
      required: [
        :id,
        :is_me,
        :private,
        :followers_count,
        :following_count,
        :follow_groups,
        :my_status,
        :follows_me,
        :buddy
      ]
    }
  end

  def person_posts_response do
    %Schema{
      title: "PersonPostsResponse",
      type: :object,
      properties: %{
        posts: %Schema{type: :array, items: Community.post()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:posts]
    }
  end

  # Profile posts ---------------------------------------------------------------

  def create_profile_post_request do
    %Schema{
      title: "ProfilePostCreateRequest",
      type: :object,
      properties: %{
        audience: %Schema{type: :string, enum: ~w(followers public)},
        body: %Schema{type: :string, maxLength: 5000},
        attachment_type: %Schema{
          type: :string,
          enum: Palee.Community.shareable_attachment_types()
        },
        attachment_id: @uuid,
        media_ids: Community.media_ids(),
        client_operation_id: %Schema{type: :string, maxLength: 120}
      },
      required: [:audience]
    }
  end
end
