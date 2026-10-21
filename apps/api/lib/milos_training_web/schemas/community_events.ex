defmodule MilosTrainingWeb.Schemas.CommunityEvents do
  @moduledoc "OpenAPI schemas for club events, attendees and guest passes (ADR-153)."

  alias MilosTrainingWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}

  defdelegate body(schema), to: Community
  defdelegate author(), to: Community

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp string(opts \\ []), do: struct(Schema, Keyword.merge([type: :string], opts))
  defp integer(opts \\ []), do: struct(Schema, Keyword.merge([type: :integer], opts))
  defp number(opts), do: struct(Schema, Keyword.merge([type: :number], opts))
  defp boolean, do: %Schema{type: :boolean}

  def place do
    object(
      "CommunityEventPlace",
      %{
        location_id: %{@nullable_uuid | description: "One of the box's locations, or null"},
        name: string(nullable: true),
        address: string(nullable: true),
        neighbourhood: string(nullable: true),
        city: string(nullable: true),
        latitude: number(nullable: true),
        longitude: number(nullable: true)
      },
      [:location_id, :name, :address, :latitude, :longitude]
    )
  end

  def my_place do
    object(
      "CommunityEventMine",
      %{
        status: string(enum: MilosTraining.Community.attendee_statuses()),
        source: string(enum: MilosTraining.Community.attendee_sources()),
        invited_by_id: @nullable_uuid,
        paid: boolean(),
        late_cancel: boolean()
      },
      [:status, :source, :paid, :late_cancel]
    )
  end

  def event do
    object(
      "CommunityEvent",
      %{
        id: @uuid,
        organization_id: @uuid,
        club_id: @uuid,
        channel_id: %{
          @nullable_uuid
          | description: "The member group this event belongs to; null for a club event"
        },
        group: %Schema{
          title: "CommunityEventGroup",
          type: :object,
          nullable: true,
          description: "The member group of a group event (free, for its members only)",
          properties: %{id: @uuid, name: string(nullable: true)},
          required: [:id]
        },
        series_id: %{@nullable_uuid | description: "Shared by every week of a weekly event"},
        post_id: %{@nullable_uuid | description: "Its card in the club feed"},
        title: string(),
        description: string(nullable: true),
        starts_at: @datetime,
        ends_at: @datetime,
        place: place(),
        capacity: integer(nullable: true, description: "Null: no limit"),
        going_count: integer(),
        waitlist_count: integer(),
        spots_left: integer(nullable: true, description: "Null: no limit"),
        price_cents: integer(description: "0: free; otherwise paid at the box"),
        currency: string(),
        open_to_non_members: boolean(),
        guest_pass_allowed: boolean(),
        guests_per_member: integer(),
        good_for_friends: %Schema{
          type: :boolean,
          description: "Staff tagged it «Καλό για φίλους»: it comes first on Φέρε φίλο"
        },
        cover_media_id: @nullable_uuid,
        cover_url: string(nullable: true),
        cancelled: boolean(),
        cancelled_at: @nullable_datetime,
        cancel_reason: string(nullable: true),
        club:
          object(
            "CommunityEventClub",
            %{id: @uuid, name: string(nullable: true), kind: string(nullable: true)},
            [:id]
          ),
        box:
          object(
            "CommunityEventBox",
            %{
              name: string(nullable: true),
              slug: string(nullable: true),
              logo_url: string(nullable: true)
            },
            []
          ),
        my: %{my_place() | nullable: true, description: "Where you stand; null if not on it"},
        goers: %Schema{
          type: :array,
          items: author(),
          nullable: true,
          description:
            "Who's going, for people who can see the club (a preview in lists, everyone on the event page); null for everyone else, who see going_count"
        },
        can_rsvp: boolean(),
        can_manage: %Schema{type: :boolean, description: "You run events at this box"},
        guests_left:
          integer(
            nullable: true,
            description: "Event page: guests you can still bring (going, guest passes on)"
          ),
        invitation: %Schema{
          type: :object,
          nullable: true,
          description: "Event page opened with an invitation link",
          properties: %{
            inviter: author(),
            usable: boolean(),
            reason:
              string(
                nullable: true,
                enum:
                  ~w(guests_not_allowed inviter_not_going guest_limit_reached event_cancelled event_started)
              )
          },
          required: [:inviter, :usable]
        }
      },
      [
        :id,
        :organization_id,
        :club_id,
        :title,
        :starts_at,
        :ends_at,
        :place,
        :going_count,
        :waitlist_count,
        :price_cents,
        :currency,
        :open_to_non_members,
        :guest_pass_allowed,
        :guests_per_member,
        :good_for_friends,
        :cancelled,
        :club,
        :box,
        :can_rsvp,
        :can_manage
      ]
    )
  end

  def events_response, do: object("CommunityEventsResponse", %{events: list(event())}, [:events])
  def event_response, do: object("CommunityEventResponse", %{event: event()}, [:event])

  def created_response do
    object(
      "CommunityEventCreatedResponse",
      %{event: event(), occurrences: integer(description: "Events made (weekly repeat)")},
      [:event, :occurrences]
    )
  end

  defp editable do
    %{
      title: string(minLength: 1, maxLength: 120),
      description: string(maxLength: 4000, nullable: true),
      starts_at: @datetime,
      ends_at: @datetime,
      location_id: %{@nullable_uuid | description: "A location of the box; or give place_name"},
      place_name: string(maxLength: 120, nullable: true),
      address: string(maxLength: 200, nullable: true),
      latitude: number(minimum: -90, maximum: 90, nullable: true),
      longitude: number(minimum: -180, maximum: 180, nullable: true),
      capacity: integer(minimum: 1, maximum: 10_000, nullable: true),
      price_cents: integer(minimum: 0, maximum: 10_000_000),
      currency: string(pattern: "^[A-Z]{3}$"),
      open_to_non_members: boolean(),
      guest_pass_allowed: boolean(),
      guests_per_member: integer(minimum: 1, maximum: 10),
      good_for_friends: %Schema{
        type: :boolean,
        description: "«Καλό για φίλους»; only when friends can come (open or guest passes)"
      },
      cover_media_id: %{@nullable_uuid | description: "A ready box photo upload"}
    }
  end

  @doc "Create body; `club_id` only on the staff route."
  def create_request(with_club? \\ false) do
    properties =
      Map.merge(editable(), %{
        channel_id: %Schema{
          type: :string,
          format: :uuid,
          description:
            "An active member group of the club: its admin (or staff) makes a group event, always free, members-only and without guest passes"
        },
        repeat_until: %Schema{
          type: :string,
          format: :date,
          description:
            "«Επανάληψη κάθε εβδομάδα» until this date (box time zone), at most #{MilosTraining.Community.event_series_max()} weeks"
        }
      })

    {properties, required} =
      if with_club?,
        do: {Map.put(properties, :club_id, @uuid), [:club_id, :title, :starts_at, :ends_at]},
        else: {properties, [:title, :starts_at, :ends_at]}

    object(
      if(with_club?, do: "StaffCommunityEventRequest", else: "CommunityEventRequest"),
      properties,
      required
    )
  end

  def update_request do
    object(
      "CommunityEventUpdateRequest",
      Map.put(editable(), :scope, scope()),
      []
    )
  end

  def cancel_request do
    object(
      "CommunityEventCancelRequest",
      %{scope: scope(), reason: string(maxLength: 300, nullable: true)},
      []
    )
  end

  defp scope,
    do:
      string(
        enum: MilosTraining.Community.event_scopes(),
        description: "This event (default) or this and following weeks"
      )

  def rsvp_request do
    object(
      "CommunityEventRsvpRequest",
      %{
        going: %Schema{type: :boolean, description: "«Θα έρθω» (true) or «Δεν θα έρθω» (false)"},
        invite_token: string(maxLength: 2000, description: "From a member's guest pass link")
      },
      [:going]
    )
  end

  def invite_response do
    object(
      "CommunityEventInviteResponse",
      %{
        token: string(),
        path: string(description: "Member-app path that opens the event with the invitation"),
        guests_left: integer(),
        expires_at: @datetime
      },
      [:token, :path, :guests_left, :expires_at]
    )
  end

  # Staff --------------------------------------------------------------------

  def stats do
    object(
      "CommunityEventStats",
      %{
        going: integer(),
        waitlisted: integer(),
        guests: integer(),
        paid: integer(),
        came: integer(),
        no_shows: integer(description: "Going but not checked in, once the event ended"),
        late_cancels: integer(description: "«Ακύρωσε αργά»: places given up within 2 hours"),
        trial_requests: integer(description: "Trial requests from the event's trial offer"),
        converted: integer(description: "Came and joined the box within 30 days")
      },
      [
        :going,
        :waitlisted,
        :guests,
        :paid,
        :came,
        :no_shows,
        :late_cancels,
        :trial_requests,
        :converted
      ]
    )
  end

  def attendee do
    object(
      "CommunityEventAttendee",
      %{
        person: author(),
        status: string(enum: MilosTraining.Community.attendee_statuses()),
        source: string(enum: MilosTraining.Community.attendee_sources()),
        invited_by: %{author() | nullable: true},
        member: %Schema{type: :boolean, description: "An active member of the box"},
        queued_at: @datetime,
        promoted_at: @nullable_datetime,
        paid_at: @nullable_datetime,
        payment_method: string(nullable: true),
        amount_cents: integer(nullable: true),
        receipt_issued: %Schema{type: :boolean, description: "Finance issued a receipt"},
        checked_in_at: @nullable_datetime,
        cancelled_at: @nullable_datetime,
        late_cancel: %Schema{
          type: :boolean,
          description:
            "«Ακύρωσε αργά»: gave up the place within 2 hours of the start (see cancelled_at)"
        },
        late_cancels_90d:
          integer(description: "This person's late cancels at the box over the last 90 days"),
        removed_by: %{author() | nullable: true},
        trial_offered_at: @nullable_datetime,
        converted_at: @nullable_datetime
      },
      [
        :person,
        :status,
        :source,
        :member,
        :queued_at,
        :receipt_issued,
        :late_cancel,
        :late_cancels_90d
      ]
    )
  end

  def staff_event do
    base = event()

    %{
      base
      | title: "StaffCommunityEvent",
        properties:
          Map.merge(base.properties, %{
            stats: stats(),
            attendees:
              object(
                "CommunityEventAttendees",
                %{
                  going: list(attendee()),
                  waitlisted: list(attendee()),
                  cancelled: list(attendee())
                },
                [:going, :waitlisted, :cancelled]
              ),
            trial_offer:
              object(
                "CommunityEventTrialOffer",
                %{
                  sent_at: @nullable_datetime,
                  can_send: boolean(),
                  recipients:
                    integer(description: "People who came, not members, not offered yet")
                },
                [:sent_at, :can_send, :recipients]
              )
          }),
        required: base.required ++ [:stats, :attendees, :trial_offer]
    }
  end

  def staff_list_event do
    base = event()

    %{
      base
      | title: "StaffCommunityEventRow",
        properties: Map.put(base.properties, :stats, stats()),
        required: base.required ++ [:stats]
    }
  end

  def staff_events_response,
    do: object("StaffCommunityEventsResponse", %{events: list(staff_list_event())}, [:events])

  def staff_event_response,
    do: object("StaffCommunityEventResponse", %{event: staff_event()}, [:event])

  def staff_created_response do
    object(
      "StaffCommunityEventCreatedResponse",
      %{event: staff_event(), occurrences: integer()},
      [:event, :occurrences]
    )
  end

  def check_in_request,
    do: object("CommunityEventCheckInRequest", %{checked_in: boolean()}, [:checked_in])

  def paid_request do
    object(
      "CommunityEventPaidRequest",
      %{payment_method: string(enum: MilosTraining.Community.event_payment_methods())},
      [:payment_method]
    )
  end

  def message_request,
    do:
      object("CommunityEventMessageRequest", %{body: string(minLength: 1, maxLength: 500)}, [
        :body
      ])

  def sent_response,
    do:
      object("CommunityEventSentResponse", %{sent: integer(description: "People notified")}, [
        :sent
      ])
end
