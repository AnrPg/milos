defmodule PaleeWeb.Schemas.Partners do
  @moduledoc """
  OpenAPI schemas of public Partners (ADR-280, ADR-169): the overview with
  eligibility, a person's profile, the deck and its badges, swipes, matches
  and their conversation (with «Κλείστε μαζί» plan messages), the
  Ρυθμίσεις switch, reports, the Palee team's reports queue and blocked
  people. Nothing here says who liked whom before it is mutual, and a
  person's gender never leaves their own profile.
  """

  alias Palee.Partners
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
  # Keys of the box vocabulary (`GET /box-vocabulary`), checked on write.
  defp disciplines, do: list(%Schema{type: :string})

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
          description: "The «Απόσταση» choices of the deck (ADR-197, ADR-280)"
        },
        default_within_km: %Schema{type: :integer},
        about_max: %Schema{type: :integer},
        daily_swipes: %Schema{type: :integer},
        report_reasons: enum_list(Partners.report_reasons())
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
        :default_within_km,
        :about_max,
        :daily_swipes,
        :report_reasons
      ]
    )
  end

  def profile do
    object(
      "PartnerProfile",
      %{
        id: @uuid,
        active: %Schema{type: :boolean},
        paused: %Schema{type: :boolean, description: "Switched off in Ρυθμίσεις"},
        show_box: %Schema{
          type: :boolean,
          description: "«Δείξε το box μου»: the card names the box of an active membership"
        },
        adult_confirmed_at: @datetime,
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
        :active,
        :paused,
        :show_box,
        :adult_confirmed_at,
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

  def eligibility do
    object(
      "PartnersEligibility",
      %{
        status: enum(~w(verified needs_verification in_review rejected suspended)),
        method: %Schema{type: :string, enum: ~w(membership sponsors), nullable: true},
        next_step: %Schema{
          type: :string,
          nullable: true,
          description: "What the verification flow asks for next (the verification side's word)"
        }
      },
      [:status, :method, :next_step]
    )
  end

  def overview do
    object(
      "PartnersOverview",
      %{
        eligibility: eligibility(),
        profile: %Schema{allOf: [profile()], nullable: true},
        swipes_remaining: %Schema{type: :integer},
        distance: enum(["available", "needs_area"]),
        options: options()
      },
      [:eligibility, :profile, :swipes_remaining, :distance, :options]
    )
  end

  def profile_request do
    object(
      "PartnerProfileRequest",
      %{
        active: %Schema{type: :boolean},
        adult_confirmed: %Schema{
          type: :boolean,
          description: "«Είμαι 18 ετών ή μεγαλύτερος/η»: required true on the first save"
        },
        show_box: %Schema{type: :boolean},
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

  def badge do
    object(
      "PartnerBadge",
      %{
        kind: enum(Partners.badge_kinds()),
        box_name: %Schema{
          type: :string,
          nullable: true,
          description: "Set for `box` only: the box of an active membership"
        }
      },
      [:kind, :box_name]
    )
  end

  def card do
    object(
      "PartnerCard",
      %{
        profile_id: @uuid,
        person: person(),
        badge: %Schema{allOf: [badge()], nullable: true},
        level: enum(Partners.levels()),
        times: enum_list(Partners.times()),
        goals: enum_list(Partners.goals()),
        disciplines: disciplines(),
        about: %Schema{type: :string, nullable: true},
        shared: shared()
      },
      [:profile_id, :person, :badge, :level, :times, :goals, :disciplines, :about, :shared]
    )
  end

  def deck do
    object(
      "PartnerDeck",
      %{
        cards: list(card()),
        swipes_remaining: %Schema{type: :integer},
        within_km: %Schema{type: :integer, enum: Partners.distances_km()}
      },
      [:cards, :swipes_remaining, :within_km]
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
        person: person(),
        partner_id: %Schema{
          type: :string,
          format: :uuid,
          description: "The other person, what a report names (`target_id`)"
        },
        status: enum(Partners.match_statuses()),
        end_reason: %Schema{type: :string, enum: Partners.end_reasons(), nullable: true},
        ended_by_me: %Schema{type: :boolean},
        read_only: %Schema{type: :boolean},
        unread: %Schema{type: :integer},
        matched_at: @datetime,
        last_message_at: @nullable_datetime
      },
      [
        :id,
        :person,
        :partner_id,
        :status,
        :end_reason,
        :ended_by_me,
        :read_only,
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
        kind: enum(Partners.plan_kinds()),
        id: @uuid,
        title: %Schema{type: :string},
        starts_at: @datetime,
        place: %Schema{type: :string, nullable: true}
      },
      [:kind, :id, :title, :starts_at, :place]
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

  def settings do
    object(
      "PartnerSettings",
      %{
        visible: %Schema{type: :boolean, description: "Whether you show in the deck"},
        has_profile: %Schema{type: :boolean}
      },
      [:visible, :has_profile]
    )
  end

  def settings_request,
    do: object("PartnerSettingsRequest", %{visible: %Schema{type: :boolean}}, [:visible])

  def report_request do
    object(
      "PartnerReportRequest",
      %{
        target_id: @uuid,
        reason: enum(Partners.report_reasons()),
        note: %Schema{type: :string, nullable: true, maxLength: Partners.report_note_max()}
      },
      [:target_id, :reason]
    )
  end

  def report_response do
    object(
      "PartnerReportResponse",
      %{
        target_id: @uuid,
        reported: %Schema{type: :boolean},
        blocked: %Schema{type: :boolean}
      },
      [:target_id, :reported, :blocked]
    )
  end

  def platform_report do
    object(
      "PlatformPartnerReport",
      %{
        id: @uuid,
        reporter: person(),
        target: person(),
        reason: enum(Partners.report_reasons()),
        note: %Schema{type: :string, nullable: true},
        status: enum(Partners.report_statuses()),
        reports_on_target: %Schema{
          type: :integer,
          description: "Reports of this status on the same person"
        },
        decided_at: @nullable_datetime,
        decision_note: %Schema{type: :string, nullable: true},
        created_at: @datetime
      },
      [
        :id,
        :reporter,
        :target,
        :reason,
        :note,
        :status,
        :reports_on_target,
        :decided_at,
        :decision_note,
        :created_at
      ]
    )
  end

  def platform_reports,
    do: object("PlatformPartnerReports", %{reports: list(platform_report())}, [:reports])

  def report_decision_request do
    object(
      "PlatformPartnerReportDecisionRequest",
      %{
        decision: enum(Partners.report_decisions()),
        note: %Schema{type: :string, nullable: true, maxLength: Partners.report_note_max()}
      },
      [:decision]
    )
  end

  def report_decision_response do
    object(
      "PlatformPartnerReportDecision",
      %{
        id: @uuid,
        target_id: @uuid,
        decision: enum(Partners.report_decisions()),
        resolved: %Schema{type: :integer, description: "Open reports on the person it closed"},
        penalized_sponsors: %Schema{type: :integer}
      },
      [:id, :target_id, :decision, :resolved, :penalized_sponsors]
    )
  end

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
