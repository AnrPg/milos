defmodule PaleeWeb.Schemas.CommunityEvents do
  @moduledoc "OpenAPI schemas for club events, attendees and guest passes (ADR-153)."

  alias PaleeWeb.Schemas.Community
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
        status: string(enum: Palee.Community.attendee_statuses()),
        source: string(enum: Palee.Community.attendee_sources()),
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
        time_zone:
          string(
            description:
              "ADR-179: the zone the event is planned in (its own when it happens away, else its gym's); times show on this clock"
          ),
        time_zone_confirmed: %Schema{
          type: :boolean,
          description:
            "The event or its gym has a confirmed zone (false: a guess, organisers are nudged)"
        },
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
        audience:
          string(
            enum: Palee.Community.event_audiences(),
            description:
              "ADR-185: who it is for: a member group only, the club (and its co-hosts), or open to everyone"
          ),
        host: host(),
        cohosts: %Schema{
          type: :array,
          items: box_face("CommunityEventCohost"),
          description: "ADR-185: boxes that co-host it (accepted)"
        },
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
            host: %Schema{type: :boolean, description: "ADR-185: the host's own invitation"},
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
        :time_zone,
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
        :audience,
        :host,
        :cohosts,
        :can_rsvp,
        :can_manage
      ]
    )
  end

  @doc "ADR-185: who hosts an event: a person (their own event) or a business."
  def host do
    object(
      "CommunityEventHost",
      %{
        kind: string(enum: ~w(person business)),
        organization_id: @uuid,
        name: string(nullable: true),
        slug: string(nullable: true, description: "The business's box page; null for a person"),
        logo_url: string(nullable: true),
        person: %{author() | nullable: true, description: "The person hosting their own event"}
      },
      [:kind, :organization_id]
    )
  end

  def box_face(title) do
    object(
      title,
      %{
        organization_id: @uuid,
        name: string(nullable: true),
        slug: string(nullable: true),
        logo_url: string(nullable: true)
      },
      [:organization_id]
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
      audience:
        string(
          enum: Palee.Community.event_audiences(),
          description:
            "ADR-185: group (its members only; needs channel_id), club, or open (everyone); sets open_to_non_members"
        ),
      guest_pass_allowed: boolean(),
      guests_per_member: integer(minimum: 1, maximum: 10),
      good_for_friends: %Schema{
        type: :boolean,
        description: "«Καλό για φίλους»; only when friends can come (open or guest passes)"
      },
      cover_media_id: %{@nullable_uuid | description: "A ready box photo upload"},
      time_zone:
        string(
          maxLength: 100,
          nullable: true,
          description:
            "ADR-179: an IANA zone for an event held away from its gym; null keeps the gym's"
        )
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
            "An active member group of the club: its admin (or staff) makes the group's event and picks its price, audience and guest passes (ADR-185)"
        },
        repeat_until: %Schema{
          type: :string,
          format: :date,
          description:
            "«Επανάληψη κάθε εβδομάδα» until this date (box time zone), at most #{Palee.Community.event_series_max()} weeks"
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
        enum: Palee.Community.event_scopes(),
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
        guests_left:
          integer(nullable: true, description: "Null for the host's own link (no guest limit)"),
        host: %Schema{type: :boolean, description: "ADR-185: the host's invitation link"},
        expires_at: @datetime
      },
      [:token, :path, :expires_at]
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
        status: string(enum: Palee.Community.attendee_statuses()),
        source: string(enum: Palee.Community.attendee_sources()),
        invited_by: %{author() | nullable: true},
        member: %Schema{type: :boolean, description: "An active member of the box"},
        queued_at: @datetime,
        promoted_at: @nullable_datetime,
        paid_at: @nullable_datetime,
        payment_method: string(nullable: true),
        amount_cents: integer(nullable: true),
        receipt_issued: %Schema{type: :boolean, description: "Finance issued a receipt"},
        refunded_at: %{
          @nullable_datetime
          | description: "ADR-185: when the payment was given back"
        },
        refund_cents: integer(nullable: true),
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
      %{payment_method: string(enum: Palee.Community.event_payment_methods())},
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

  # ADR-185: hosts --------------------------------------------------------------

  def hosts_response do
    club =
      object(
        "CommunityEventHostClub",
        %{id: @uuid, name: string(nullable: true), kind: string()},
        [:id, :kind]
      )

    choice =
      object(
        "CommunityEventHostChoice",
        %{
          kind: string(enum: ~w(self business)),
          id: string(description: "\"self\" for «Ως εγώ», else the business's organisation id"),
          organization_id: %{
            @nullable_uuid
            | description: "The organisation it hosts as (null before your first own event)"
          },
          slug: string(nullable: true),
          name: string(nullable: true),
          logo_url: string(nullable: true),
          clubs: list(club)
        },
        [:kind, :id, :clubs]
      )

    object("CommunityEventHostsResponse", %{hosts: list(choice)}, [:hosts])
  end

  def host_create_request do
    base = create_request()

    %{
      base
      | title: "CommunityEventHostedRequest",
        properties:
          Map.merge(base.properties, %{
            host:
              string(
                maxLength: 64,
                description:
                  "«Διοργάνωση ως»: \"self\" (default) or the organisation id of a business where you run events"
              ),
            club_id: %{
              @uuid
              | description: "As a business: which of its clubs (its gym club by default)"
            }
          })
    }
  end

  def view_response,
    do: object("CommunityEventViewResponse", %{counted: boolean()}, [:counted])

  # ADR-185: the organiser console -----------------------------------------------

  def refund_request do
    object(
      "CommunityEventRefundRequest",
      %{
        amount_cents:
          integer(
            minimum: 1,
            maximum: 10_000_000,
            nullable: true,
            description: "What was given back; all of it when left out"
          )
      },
      []
    )
  end

  @console_scope ~w(all upcoming past)
  def console_scopes, do: @console_scope

  defp event_line do
    %{
      event_id: @uuid,
      title: string(),
      starts_at: @datetime,
      ends_at: @datetime,
      time_zone: string(nullable: true),
      cancelled_at: @nullable_datetime
    }
  end

  @money ~w(paid_count paid_cents refunded_count refunded_cents net_cents outstanding_count
            outstanding_cents)a

  def finances_response do
    money = Map.new(@money, &{&1, integer()})

    row =
      object(
        "CommunityEventFinanceRow",
        Map.merge(event_line(), Map.merge(money, %{currency: string(), price_cents: integer()})),
        [:event_id, :title, :starts_at, :currency, :price_cents | @money]
      )

    total =
      object(
        "CommunityEventFinanceTotal",
        Map.merge(money, %{currency: string(), events: integer()}),
        [:currency, :events | @money]
      )

    object(
      "CommunityEventFinancesResponse",
      %{events: list(row), totals: %{list(total) | description: "One row per currency"}},
      [:events, :totals]
    )
  end

  @counts ~w(views viewers rsvps going waitlisted came)a

  def analytics_response do
    counts = Map.new(@counts, &{&1, integer()})

    rates = %{
      attendance_rate:
        integer(nullable: true, description: "Came of those going, % (once it ended)"),
      conversion_rate: integer(nullable: true, description: "RSVPs of distinct viewers, %")
    }

    row =
      object(
        "CommunityEventAnalyticsRow",
        event_line() |> Map.merge(counts) |> Map.merge(rates) |> Map.put(:cancelled, integer()),
        [:event_id, :title, :starts_at | @counts]
      )

    total =
      object(
        "CommunityEventAnalyticsTotal",
        counts |> Map.merge(rates) |> Map.put(:events, integer()),
        [:events | @counts]
      )

    object(
      "CommunityEventAnalyticsResponse",
      %{events: list(row), totals: total},
      [:events, :totals]
    )
  end

  # ADR-185: co-hosts --------------------------------------------------------------

  def cohosts_response do
    row =
      object(
        "CommunityEventCohostRow",
        %{
          id: @uuid,
          status: string(enum: Palee.Community.cohost_statuses()),
          box: box_face("CommunityEventCohostBox"),
          invited_at: @datetime,
          responded_at: @nullable_datetime
        },
        [:id, :status, :box, :invited_at]
      )

    object("CommunityEventCohostsResponse", %{cohosts: list(row)}, [:cohosts])
  end

  def cohost_invite_request do
    object(
      "CommunityEventCohostInviteRequest",
      %{slug: string(minLength: 1, maxLength: 200, description: "The box page's address")},
      [:slug]
    )
  end

  def cohost_requests_response do
    request =
      object(
        "CommunityEventCohostRequest",
        %{
          id: @uuid,
          status: string(enum: Palee.Community.cohost_statuses()),
          answerable: boolean(),
          can_send_trial_offer: boolean(),
          trial_offer_sent_at: @nullable_datetime,
          invited_at: @datetime,
          responded_at: @nullable_datetime,
          event:
            object(
              "CommunityEventCohostRequestEvent",
              %{
                id: @uuid,
                title: string(),
                starts_at: @datetime,
                ends_at: @datetime,
                time_zone: string(nullable: true),
                cancelled_at: @nullable_datetime,
                audience: string(enum: Palee.Community.event_audiences()),
                weekly: boolean()
              },
              [:id, :title, :starts_at, :ends_at, :audience, :weekly]
            ),
          host: box_face("CommunityEventCohostRequestHost")
        },
        [:id, :status, :answerable, :can_send_trial_offer, :invited_at, :event, :host]
      )

    object("CommunityEventCohostRequestsResponse", %{requests: list(request)}, [:requests])
  end

  def cohost_answer_request do
    object(
      "CommunityEventCohostAnswerRequest",
      %{
        answer:
          string(
            enum: ~w(accepted declined removed),
            description: "Accept or decline a request; removed withdraws after accepting"
          )
      },
      [:answer]
    )
  end
end
