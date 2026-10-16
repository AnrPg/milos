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
          enum: ~w(announcements wod challenges class_slot season custom)
        },
        name: %Schema{type: :string, nullable: true, description: "Null for built-in channels"},
        write_policy: %Schema{
          type: :string,
          enum: ~w(staff members participants system_and_members)
        },
        membership: %Schema{type: :string, enum: ~w(everyone opt_in invite)},
        joined: %Schema{type: :boolean, description: "Its posts reach your feed"},
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
        organization_slug: %Schema{type: :string},
        kind: %Schema{type: :string, enum: ~w(gym open member_group pt_squad season)},
        name: %Schema{type: :string},
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

  defp notify_levels, do: MilosTraining.Community.notify_level_options()
end
