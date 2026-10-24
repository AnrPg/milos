defmodule PaleeWeb.Schemas.Partners do
  @moduledoc """
  OpenAPI schemas of Partners (ADR-169): a member's profile in a club, the
  deck, swipes, matches and their conversation, «Κλείστε μαζί», the
  Ρυθμίσεις switch and blocked people. Nothing here says who liked whom
  before it is mutual, and a person's gender never leaves their own profile.
  """

  alias Palee.{Organizations, Partners}
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp enum(values), do: %Schema{type: :string, enum: values}
  defp enum_list(values), do: list(enum(values))
  defp disciplines, do: enum_list(Organizations.box_disciplines())

  def person do
    object(
      "PartnerPerson",
      %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      },
      [:id, :nickname, :avatar_url]
    )
  end

  def options do
    object(
      "PartnerOptions",
      %{
        levels: enum_list(Partners.levels()),
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        genders: enum_list(Partners.genders()),
        gender_preferences: enum_list(Partners.gender_preferences()),
        max_goals: %Schema{type: :integer},
        disciplines: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Box vocabulary keys a profile may name (ADR-197)"
        },
        max_disciplines: %Schema{type: :integer},
        distances_km: %Schema{
          type: :array,
          items: %Schema{type: :integer},
          description: "The «Απόσταση» choices of an open club's deck (ADR-197)"
        },
        about_max: %Schema{type: :integer},
        daily_swipes: %Schema{type: :integer}
      },
      [
        :levels,
        :times,
        :goals,
        :genders,
        :gender_preferences,
        :max_goals,
        :disciplines,
        :max_disciplines,
        :distances_km,
        :about_max,
        :daily_swipes
      ]
    )
  end

  def profile do
    object(
      "PartnerProfile",
      %{
        id: @uuid,
        club_id: @uuid,
        active: %Schema{type: :boolean},
        suspended: %Schema{type: :boolean, description: "Staff hid it after a report"},
        level: enum(Partners.levels()),
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        disciplines: disciplines(),
        about: %Schema{type: :string, nullable: true},
        gender: %Schema{
          type: :string,
          enum: Partners.genders(),
          nullable: true,
          description: "Only used to honour preferences; never shown to anyone"
        },
        gender_preference: enum(Partners.gender_preferences()),
        updated_at: @datetime
      },
      [
        :id,
        :club_id,
        :active,
        :suspended,
        :level,
        :times,
        :goals,
        :disciplines,
        :about,
        :gender,
        :gender_preference
      ]
    )
  end

  def overview do
    object(
      "PartnersClubOverview",
      %{
        club_id: @uuid,
        offered: %Schema{type: :boolean},
        unavailable_reason: %Schema{
          type: :string,
          enum: ["disabled", "not_offered"],
          nullable: true
        },
        member: %Schema{
          type: :boolean,
          description: "Whether the viewer is a member of the club now"
        },
        profile: %Schema{allOf: [profile()], nullable: true},
        swipes_remaining: %Schema{type: :integer},
        distance: %Schema{
          type: :string,
          enum: ["available", "needs_area"],
          nullable: true,
          description:
            "Open clubs only (ADR-197): «Απόσταση» works once the viewer has «Η περιοχή μου» and shows in Γύρω μου"
        },
        options: options()
      },
      [
        :club_id,
        :offered,
        :unavailable_reason,
        :member,
        :profile,
        :swipes_remaining,
        :distance,
        :options
      ]
    )
  end

  def profile_request do
    object(
      "PartnerProfileRequest",
      %{
        active: %Schema{type: :boolean},
        level: enum(Partners.levels()),
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        disciplines: %{disciplines() | maxItems: Partners.max_disciplines()},
        about: %Schema{type: :string, nullable: true, maxLength: Partners.about_max()},
        gender: %Schema{type: :string, enum: Partners.genders(), nullable: true},
        gender_preference: enum(Partners.gender_preferences())
      },
      []
    )
  end

  def profile_response, do: object("PartnerProfileResponse", %{profile: profile()}, [:profile])

  def shared do
    object(
      "PartnerShared",
      %{
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        disciplines: disciplines(),
        same_level: %Schema{type: :boolean}
      },
      [:times, :goals, :disciplines, :same_level]
    )
  end

  def card do
    object(
      "PartnerCard",
      %{
        profile_id: @uuid,
        person: person(),
        level: enum(Partners.levels()),
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        disciplines: disciplines(),
        about: %Schema{type: :string, nullable: true},
        shared: shared()
      },
      [:profile_id, :person, :level, :times, :goals, :disciplines, :about, :shared]
    )
  end

  def deck do
    object(
      "PartnerDeck",
      %{club_id: @uuid, cards: list(card()), swipes_remaining: %Schema{type: :integer}},
      [:club_id, :cards, :swipes_remaining]
    )
  end

  def swipe_request do
    object(
      "PartnerSwipeRequest",
      %{target_id: @uuid, direction: enum(Partners.swipe_directions())},
      [:target_id, :direction]
    )
  end

  def match do
    object(
      "PartnerMatch",
      %{
        id: @uuid,
        club_id: @uuid,
        club_name: %Schema{type: :string, nullable: true},
        person: person(),
        partner_profile_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The other person's profile in the club, what a report names"
        },
        status: enum(Partners.match_statuses()),
        end_reason: %Schema{type: :string, enum: Partners.end_reasons(), nullable: true},
        ended_by_me: %Schema{type: :boolean},
        read_only: %Schema{type: :boolean},
        plannable: %Schema{type: :boolean, description: "«Κλείστε μαζί» offers the gym's classes"},
        unread: %Schema{type: :integer},
        matched_at: @datetime,
        last_message_at: @nullable_datetime
      },
      [
        :id,
        :club_id,
        :club_name,
        :person,
        :partner_profile_id,
        :status,
        :end_reason,
        :ended_by_me,
        :read_only,
        :plannable,
        :unread,
        :matched_at,
        :last_message_at
      ]
    )
  end

  def swipe_response do
    object(
      "PartnerSwipeResponse",
      %{
        target_id: @uuid,
        direction: enum(Partners.swipe_directions()),
        match: %Schema{
          allOf: [match()],
          nullable: true,
          description: "Set when the like was mutual"
        },
        swipes_remaining: %Schema{type: :integer}
      },
      [:target_id, :direction, :match, :swipes_remaining]
    )
  end

  def undo_response,
    do:
      object("PartnerUndoResponse", %{target_id: @uuid, undone: %Schema{type: :boolean}}, [
        :target_id,
        :undone
      ])

  def matches_response, do: object("PartnerMatches", %{matches: list(match())}, [:matches])

  def match_ended,
    do:
      object("PartnerMatchEnded", %{id: @uuid, status: enum(Partners.match_statuses())}, [
        :id,
        :status
      ])

  def plan do
    object(
      "PartnerPlan",
      %{
        class_id: @uuid,
        name: %Schema{type: :string, nullable: true},
        scheduled_at: @datetime,
        duration_minutes: %Schema{type: :integer, nullable: true}
      },
      [:class_id, :name, :scheduled_at, :duration_minutes]
    )
  end

  def message do
    object(
      "PartnerMessage",
      %{
        id: @uuid,
        match_id: @uuid,
        kind: enum(~w(text plan)),
        body: %Schema{type: :string, nullable: true, maxLength: Partners.message_body_max()},
        plan: %Schema{allOf: [plan()], nullable: true},
        mine: %Schema{type: :boolean},
        author: person(),
        created_at: @datetime
      },
      [:id, :match_id, :kind, :body, :plan, :mine, :author, :created_at]
    )
  end

  def message_page do
    object(
      "PartnerMessagePage",
      %{
        messages: list(message()),
        next_cursor: %Schema{type: :string, nullable: true},
        read_only: %Schema{type: :boolean},
        unread: %Schema{type: :integer}
      },
      [:messages, :next_cursor, :read_only, :unread]
    )
  end

  def message_request do
    object(
      "PartnerMessageRequest",
      %{body: %Schema{type: :string, minLength: 1, maxLength: Partners.message_body_max()}},
      [:body]
    )
  end

  def message_response, do: object("PartnerMessageResponse", %{message: message()}, [:message])

  def read_response, do: object("PartnerMessagesRead", %{read: %Schema{type: :integer}}, [:read])

  def session do
    object(
      "PartnerSession",
      %{
        class_id: @uuid,
        name: %Schema{type: :string, nullable: true},
        scheduled_at: @datetime,
        duration_minutes: %Schema{type: :integer, nullable: true},
        spots_remaining: %Schema{type: :integer},
        booked_by_me: %Schema{type: :boolean},
        booked_by_partner: %Schema{type: :boolean},
        shared_time: %Schema{type: :boolean, description: "In a time both of you chose"}
      },
      [
        :class_id,
        :name,
        :scheduled_at,
        :duration_minutes,
        :spots_remaining,
        :booked_by_me,
        :booked_by_partner,
        :shared_time
      ]
    )
  end

  def sessions_response do
    object(
      "PartnerSessions",
      %{
        available: %Schema{type: :boolean},
        timezone: %Schema{type: :string, nullable: true},
        sessions: list(session())
      },
      [:available, :timezone, :sessions]
    )
  end

  def plan_request do
    object(
      "PartnerPlanRequest",
      %{
        class_id: @uuid,
        body: %Schema{type: :string, nullable: true, maxLength: Partners.message_body_max()}
      },
      [:class_id]
    )
  end

  def settings do
    object(
      "PartnerSettings",
      %{
        visible: %Schema{type: :boolean, description: "Whether any of your profiles is on"},
        clubs: %Schema{type: :integer, description: "Clubs where you have a profile"},
        club_ids: list(@uuid)
      },
      [:visible, :clubs, :club_ids]
    )
  end

  def settings_request,
    do: object("PartnerSettingsRequest", %{visible: %Schema{type: :boolean}}, [:visible])

  def block_request, do: object("BlockPersonRequest", %{user_id: @uuid}, [:user_id])

  def block_response do
    object(
      "BlockPersonResponse",
      %{user_id: @uuid, blocked: %Schema{type: :boolean}},
      [:user_id, :blocked]
    )
  end

  def blocks_response do
    object(
      "BlockedPeople",
      %{
        blocks:
          list(
            object("BlockedPerson", %{person: person(), blocked_at: @datetime}, [
              :person,
              :blocked_at
            ])
          )
      },
      [:blocks]
    )
  end
end
