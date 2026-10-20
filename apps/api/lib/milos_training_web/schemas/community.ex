defmodule MilosTrainingWeb.Schemas.Community do
  @moduledoc "OpenAPI schemas for clubs, channels and posts (ADR-138)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def channel do
    %Schema{
      title: "CommunityChannel",
      type: :object,
      properties: %{
        id: @uuid,
        kind: %Schema{
          type: :string,
          enum: ~w(announcements wod challenges class_slot season custom member_group general)
        },
        name: %Schema{type: :string, nullable: true, description: "Null for built-in channels"},
        description: %Schema{type: :string, nullable: true},
        status: %Schema{
          type: :string,
          enum: ~w(pending active declined),
          description: "A member group waits for staff while pending"
        },
        join_policy: %Schema{type: :string, enum: ~w(open request), nullable: true},
        created_by_id: %Schema{type: :string, format: :uuid, nullable: true},
        admin: %Schema{type: :boolean, description: "You are an admin of this member group"},
        requested: %Schema{type: :boolean, description: "You asked to join this member group"},
        can_moderate: %Schema{type: :boolean},
        can_pin: %Schema{type: :boolean},
        write_policy: %Schema{
          type: :string,
          enum: ~w(staff members participants system_and_members)
        },
        membership: %Schema{type: :string, enum: ~w(everyone opt_in invite)},
        joined: %Schema{type: :boolean, description: "Its posts reach your feed"},
        participant: %Schema{type: :boolean, description: "You are a member of this channel"},
        suggested: %Schema{
          type: :boolean,
          description: "Offered to you (you often book its class) and not joined yet"
        },
        context_type: %Schema{type: :string, nullable: true},
        can_post: %Schema{type: :boolean},
        can_leave: %Schema{type: :boolean, description: "You may join or leave it yourself"}
      },
      required: [:id, :kind, :write_policy, :membership, :joined, :can_post, :can_leave]
    }
  end

  def club do
    %Schema{
      title: "CommunityClub",
      type: :object,
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        organization_slug: %Schema{
          type: :string,
          nullable: true,
          description: "Null for an open club of a gym you can't see"
        },
        organization_name: %Schema{type: :string, nullable: true},
        kind: %Schema{type: :string, enum: ~w(gym open member_group pt_squad season)},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        join_policy: %Schema{type: :string},
        logo_url: %Schema{type: :string, nullable: true},
        primary_color: %Schema{type: :string, nullable: true},
        role: %Schema{type: :string, enum: ~w(member staff)},
        notify_level: %Schema{type: :string, enum: notify_levels()},
        channels: %Schema{type: :array, items: channel()}
      },
      required: [
        :id,
        :organization_id,
        :organization_slug,
        :kind,
        :name,
        :role,
        :notify_level,
        :channels
      ]
    }
  end

  def clubs_response do
    %Schema{
      title: "CommunityClubsResponse",
      type: :object,
      properties: %{clubs: %Schema{type: :array, items: club()}},
      required: [:clubs]
    }
  end

  def notify_request do
    %Schema{
      title: "CommunityNotifyLevelRequest",
      type: :object,
      properties: %{notify_level: %Schema{type: :string, enum: notify_levels()}},
      required: [:notify_level]
    }
  end

  def notify_response do
    %Schema{
      title: "CommunityNotifyLevelResponse",
      type: :object,
      properties: %{club_id: @uuid, notify_level: %Schema{type: :string, enum: notify_levels()}},
      required: [:club_id, :notify_level]
    }
  end

  def channel_membership_response do
    %Schema{
      title: "CommunityChannelMembershipResponse",
      type: :object,
      properties: %{channel_id: @uuid, joined: %Schema{type: :boolean}},
      required: [:channel_id, :joined]
    }
  end

  def datetime, do: @datetime

  def attachment_types, do: MilosTraining.Community.attachment_types()

  def post do
    %Schema{
      title: "CommunityPost",
      type: :object,
      description:
        "A club post (origin club: club and channel set; channel null on a box's public post seen from outside the club) or a profile post (origin profile: no club)",
      properties: %{
        id: @uuid,
        origin: %Schema{type: :string, enum: ~w(club profile)},
        audience: %Schema{type: :string, enum: ~w(club_channel followers public)},
        club: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            kind: %Schema{type: :string},
            name: %Schema{type: :string},
            organization_slug: %Schema{type: :string, nullable: true},
            logo_url: %Schema{type: :string, nullable: true},
            primary_color: %Schema{type: :string, nullable: true}
          },
          required: [:id, :name]
        },
        channel: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            kind: %Schema{type: :string, nullable: true},
            name: %Schema{type: :string, nullable: true}
          },
          required: [:id]
        },
        author: author(),
        body: %Schema{type: :string, nullable: true},
        attachment_type: %Schema{type: :string, enum: attachment_types(), nullable: true},
        attachment_id: %Schema{type: :string, format: :uuid, nullable: true},
        attachment: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: true,
          description:
            "What the attached journal entry showed when it was shared: title, workout_type, scale_level_slug, occurred_at, duration_seconds, section_scores; for a PR title, score, unit, occurred_on"
        },
        event: %{
          MilosTrainingWeb.Schemas.CommunityEvents.event()
          | title: "CommunityPostEvent",
            nullable: true,
            description:
              "The event as you see it now, when the post is an event card (attachment_type event)"
        },
        pinned: %Schema{type: :boolean},
        hidden: %Schema{type: :boolean},
        kudos_count: %Schema{type: :integer},
        comment_count: %Schema{type: :integer},
        kudos_by_me: %Schema{type: :boolean},
        can_delete: %Schema{type: :boolean},
        can_moderate: %Schema{type: :boolean},
        can_pin: %Schema{type: :boolean},
        can_report: %Schema{type: :boolean},
        inserted_at: @datetime
      },
      required: [
        :id,
        :origin,
        :audience,
        :club,
        :channel,
        :author,
        :pinned,
        :hidden,
        :kudos_count,
        :comment_count,
        :kudos_by_me,
        :can_delete,
        :can_moderate,
        :can_pin,
        :inserted_at
      ]
    }
  end

  def author do
    %Schema{
      title: "CommunityAuthor",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      },
      required: [:id]
    }
  end

  def feed_response do
    %Schema{
      title: "CommunityFeedPage",
      type: :object,
      properties: %{
        pinned: %Schema{type: :array, items: post()},
        posts: %Schema{type: :array, items: post()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:pinned, :posts]
    }
  end

  def post_response do
    %Schema{
      title: "CommunityPostResponse",
      type: :object,
      properties: %{post: post()},
      required: [:post]
    }
  end

  def create_post_request do
    %Schema{
      title: "CommunityPostCreateRequest",
      type: :object,
      properties: %{
        channel_id: @uuid,
        audience: %Schema{
          type: :string,
          enum: ~w(club_channel public),
          description:
            "public (staff only) also shows the post on the box page and to its followers"
        },
        body: %Schema{type: :string, maxLength: 5000},
        attachment_type: %Schema{
          type: :string,
          enum: MilosTraining.Community.shareable_attachment_types()
        },
        attachment_id: @uuid,
        client_operation_id: %Schema{type: :string, maxLength: 120}
      },
      required: [:channel_id]
    }
  end

  def flag_request(name) do
    %Schema{
      title: "CommunityPost#{Macro.camelize(Atom.to_string(name))}Request",
      type: :object,
      properties: %{name => %Schema{type: :boolean}},
      required: [name]
    }
  end

  def comment do
    %Schema{
      title: "CommunityComment",
      type: :object,
      properties: %{
        id: @uuid,
        post_id: @uuid,
        author: author(),
        body: %Schema{type: :string},
        inserted_at: @datetime,
        hidden: %Schema{type: :boolean},
        can_delete: %Schema{type: :boolean},
        can_moderate: %Schema{type: :boolean},
        can_report: %Schema{type: :boolean}
      },
      required: [:id, :post_id, :author, :body, :inserted_at, :can_delete]
    }
  end

  def comments_response do
    %Schema{
      title: "CommunityCommentsResponse",
      type: :object,
      properties: %{comments: %Schema{type: :array, items: comment()}},
      required: [:comments]
    }
  end

  def comment_response do
    %Schema{
      title: "CommunityCommentResponse",
      type: :object,
      properties: %{comment: comment()},
      required: [:comment]
    }
  end

  def comment_request do
    %Schema{
      title: "CommunityCommentRequest",
      type: :object,
      properties: %{body: %Schema{type: :string, minLength: 1, maxLength: 2000}},
      required: [:body]
    }
  end

  defp notify_levels, do: MilosTraining.Community.notify_level_options()

  def wod_today_response do
    entry = %Schema{
      title: "WodLeaderboardEntry",
      type: :object,
      properties: %{
        rank: %Schema{type: :integer},
        user_id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        scale_level_slug: %Schema{type: :string, nullable: true},
        value: %Schema{type: :string, nullable: true},
        unit: %Schema{type: :string, nullable: true},
        me: %Schema{type: :boolean},
        opted_in: %Schema{
          type: :boolean,
          description: "False only on your own row before you opt in to leaderboards"
        }
      },
      required: [:rank, :user_id, :me, :opted_in]
    }

    %Schema{
      title: "WodTodayCard",
      type: :object,
      properties: %{
        date: %Schema{type: :string, format: :date},
        channel_id: %Schema{type: :string, format: :uuid, nullable: true},
        workout: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            title: %Schema{type: :string},
            type: %Schema{type: :string, nullable: true}
          },
          required: [:id, :title]
        },
        classes: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{id: @uuid, scheduled_at: @datetime},
            required: [:id, :scheduled_at]
          }
        },
        score: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: %Schema{type: :string},
            name: %Schema{type: :string, nullable: true},
            score_type: %Schema{type: :string},
            unit: %Schema{type: :string, nullable: true}
          },
          required: [:id, :score_type]
        },
        leaderboard: %Schema{type: :array, items: entry},
        logged_by_me: %Schema{type: :boolean}
      },
      required: [:date, :classes, :leaderboard, :logged_by_me]
    }
  end
end
