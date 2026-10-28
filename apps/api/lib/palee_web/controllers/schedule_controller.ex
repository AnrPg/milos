defmodule PaleeWeb.ScheduleController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias Palee.Application.{
    CheckInOpenGym,
    CheckInToClass,
    GetScheduleCalendar,
    JoinClassWaitlist,
    SubmitBooking,
    SubmitGuestBooking,
    WithdrawBooking
  }

  alias Palee.Facility
  alias PaleeWeb.ParamExtractor
  alias PaleeWeb.Schemas.Facility, as: FacilitySchemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :index,
              :create_booking,
              :join_waitlist,
              :create_guest_booking,
              :check_in,
              :check_in_class
            ]

  @location_schema FacilitySchemas.location_schema()

  @date_param %Parameter{
    name: :start_date,
    in: :query,
    description: "Calendar window start date",
    required: false,
    schema: %Schema{type: :string, format: :date}
  }

  @start_at_param %Parameter{
    name: :start_at,
    in: :query,
    description: "Explicit UTC window start datetime",
    required: false,
    schema: %Schema{type: :string, format: :"date-time"}
  }

  @end_at_param %Parameter{
    name: :end_at,
    in: :query,
    description: "Explicit UTC window end datetime",
    required: false,
    schema: %Schema{type: :string, format: :"date-time"}
  }

  @days_param %Parameter{
    name: :days,
    in: :query,
    description: "Window size in days",
    required: false,
    schema: %Schema{type: :integer, enum: [1, 3, 7, 30]}
  }

  @class_types_param %Parameter{
    name: :class_type_ids,
    in: :query,
    description: "Optional class type filters",
    required: false,
    schema: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
    style: :form,
    explode: true
  }

  operation(:index,
    summary: "Get the schedule window",
    parameters: [@date_param, @start_at_param, @end_at_param, @days_param, @class_types_param],
    responses: [
      ok:
        {"Schedule", "application/json",
         %Schema{
           type: :object,
           properties: %{
             start_date: %Schema{type: :string, format: :date},
             end_date: %Schema{type: :string, format: :date},
             days: %Schema{type: :integer},
             class_types: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             },
             locations: %Schema{type: :array, items: @location_schema},
             day_workouts: %Schema{
               type: :array,
               description:
                 "ADR-224, staff only (empty for others): the WOD of each day in the window, " <>
                   "for every class (class_type_id null) or one class type, and every branch " <>
                   "(location_id null) or one.",
               items: %Schema{
                 type: :object,
                 additionalProperties: true,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   local_date: %Schema{type: :string, format: :date},
                   class_type_id: %Schema{type: :string, format: :uuid, nullable: true},
                   location_id: %Schema{type: :string, format: :uuid, nullable: true},
                   master_workout_id: %Schema{type: :string, format: :uuid},
                   workout: %Schema{
                     type: :object,
                     nullable: true,
                     properties: %{
                       id: %Schema{type: :string, format: :uuid},
                       title: %Schema{type: :string},
                       type: %Schema{type: :string, nullable: true}
                     }
                   }
                 },
                 required: [:id, :local_date, :class_type_id, :location_id, :master_workout_id]
               }
             },
             coaches: %Schema{
               type: :array,
               description: "The coaches of the window's classes.",
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   nickname: %Schema{type: :string},
                   avatar_url: %Schema{type: :string, nullable: true}
                 },
                 required: [:id, :nickname, :avatar_url]
               }
             },
             slots: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 additionalProperties: true,
                 properties: %{
                   day_workout_id: %Schema{
                     type: :string,
                     format: :uuid,
                     nullable: true,
                     description: "ADR-224: the day WOD the class's WOD comes from."
                   },
                   workout_source: %Schema{
                     type: :string,
                     nullable: true,
                     enum: ["day", "class"],
                     description:
                       "ADR-224: day = inherited from the day's WOD, class = set on the class."
                   },
                   space_id: %Schema{type: :string, format: :uuid, nullable: true},
                   space: %Schema{
                     type: :object,
                     nullable: true,
                     description: "ADR-202: the room or area of the branch the class is held in.",
                     properties: %{
                       id: %Schema{type: :string, format: :uuid},
                       name: %Schema{type: :string}
                     },
                     required: [:id, :name]
                   },
                   space_overlap: %Schema{
                     type: :boolean,
                     description:
                       "Staff only: another class is in the same space at an overlapping time (a warning, not a block)."
                   },
                   space_unavailable: %Schema{
                     type: :boolean,
                     description:
                       "Staff only: the space was made unavailable for this class's time after it was planned."
                   },
                   cancel_free_until: %Schema{
                     type: :string,
                     format: :"date-time",
                     nullable: true,
                     description:
                       "Members only: until when withdrawing is free; null when no cutoff applies."
                   },
                   friends_going: %Schema{
                     type: :array,
                     description:
                       "Members only: people the viewer follows who share their bookings and hold a place in this class (the «Φίλοι» chip).",
                     items: %Schema{
                       type: :object,
                       properties: %{
                         id: %Schema{type: :string, format: :uuid},
                         nickname: %Schema{type: :string, nullable: true},
                         avatar_url: %Schema{type: :string, nullable: true}
                       },
                       required: [:id]
                     }
                   },
                   covered_by_package: %Schema{
                     type: :boolean,
                     description:
                       "Members only: whether the viewer's package includes this class, regardless of visits left."
                   },
                   workout: %Schema{
                     type: :object,
                     nullable: true,
                     additionalProperties: true,
                     properties: %{
                       focus: %Schema{
                         type: :array,
                         description: "What the workout trains, read from its movements.",
                         items: %Schema{
                           type: :string,
                           enum:
                             ~w(strength endurance gymnastics olympic_lifting mobility legs core upper_body)
                         }
                       }
                     }
                   }
                 }
               }
             }
           },
           required: [:start_date, :end_date, :days, :class_types, :day_workouts, :slots]
         }}
    ]
  )

  @booking_response %Schema{
    type: :object,
    properties: %{booking: %Schema{type: :object, additionalProperties: true}},
    required: [:booking]
  }

  @error_response %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}}
  }

  operation(:create_booking,
    summary: "Book a schedule slot",
    description:
      "Optionally idempotent per `client_operation_id` (ADR-120): replaying the same id for " <>
        "the same slot returns the original booking with 200 and no new reservation, " <>
        "notification, or broadcast; reusing it for another slot returns 409 " <>
        "`idempotency_key_conflict`.",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              slot_id: %Schema{type: :string, format: :uuid},
              client_operation_id: %Schema{
                type: :string,
                format: :uuid,
                nullable: true,
                description: "Stable client operation id for offline replay dedupe"
              }
            },
            required: [:slot_id]
          }
        }
      }
    },
    responses: [
      created: {"Booking", "application/json", @booking_response},
      ok: {"Replayed booking", "application/json", @booking_response},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}},
      conflict:
        {"Slot full, already booked, or operation id conflict", "application/json",
         @error_response},
      unprocessable_entity: {"Invalid request", "application/json", @error_response}
    ]
  )

  def index(conn, params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetScheduleCalendar.call(conn.assigns.tenant_context, actor, params) do
      json(conn, payload)
    end
  end

  def create_booking(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    body = conn.body_params |> normalize_body_params(params)
    slot_id = ParamExtractor.get(body, "slot_id")
    operation_id = ParamExtractor.get(body, "client_operation_id")

    with {:ok, booking, outcome} <-
           SubmitBooking.call(conn.assigns.tenant_context, actor, slot_id,
             client_operation_id: operation_id
           ) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(%{booking: booking})
    end
  end

  operation(:delete_booking,
    summary: "Withdraw a pending or approved booking",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Withdrawal result", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Not the owner", "application/json", %Schema{type: :object}}
    ]
  )

  def delete_booking(conn, %{"id" => booking_id}) do
    actor = GuardianPlug.current_resource(conn)

    case WithdrawBooking.call(conn.assigns.tenant_context, actor.id, booking_id) do
      {:ok, booking} ->
        json(conn, %{ok: true, late_cancellation: Map.get(booking, :late_cancellation, false)})

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :forbidden} ->
        {:error, :forbidden}

      {:error, _} ->
        {:error, :unprocessable_entity}
    end
  end

  @booking_response %Schema{
    type: :object,
    properties: %{booking: %Schema{type: :object, additionalProperties: true}},
    required: [:booking]
  }

  operation(:join_waitlist,
    summary: "Join the waitlist of a full class",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{slot_id: %Schema{type: :string, format: :uuid}},
            required: [:slot_id]
          }
        }
      }
    },
    responses: [
      created: {"Waitlist entry", "application/json", @booking_response},
      conflict: {"Class not full or already booked", "application/json", %Schema{type: :object}},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}}
    ]
  )

  def join_waitlist(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    slot_id = Map.get(conn.body_params, :slot_id)

    with {:ok, entry} <- JoinClassWaitlist.call(conn.assigns.tenant_context, actor, slot_id) do
      conn
      |> put_status(:created)
      |> json(%{booking: entry})
    end
  end

  operation(:create_guest_booking,
    summary: "Book a named guest into a class on a guest pass",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              slot_id: %Schema{type: :string, format: :uuid},
              guest_name: %Schema{type: :string, minLength: 2, maxLength: 80}
            },
            required: [:slot_id, :guest_name]
          }
        }
      }
    },
    responses: [
      created: {"Guest booking", "application/json", @booking_response},
      conflict:
        {"Class full or guest already booked", "application/json", %Schema{type: :object}},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}}
    ]
  )

  def create_guest_booking(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    slot_id = Map.get(conn.body_params, :slot_id)
    guest_name = Map.get(conn.body_params, :guest_name)

    with {:ok, booking} <-
           SubmitGuestBooking.call(conn.assigns.tenant_context, actor, slot_id, guest_name) do
      conn
      |> put_status(:created)
      |> json(%{booking: booking})
    end
  end

  operation(:locations,
    summary: "List the gym's locations",
    responses: [
      ok:
        {"Locations", "application/json",
         %Schema{
           type: :object,
           properties: %{
             locations: %Schema{type: :array, items: @location_schema}
           },
           required: [:locations]
         }}
    ]
  )

  def locations(conn, _params) do
    json(conn, %{locations: Facility.list_locations(conn.assigns.tenant_context)})
  end

  operation(:check_in,
    summary: "Check in to open gym",
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{location_id: %Schema{type: :string, format: :uuid, nullable: true}}
          }
        }
      }
    },
    responses: [
      created:
        {"Check-in", "application/json",
         %Schema{
           type: :object,
           properties: %{check_in: FacilitySchemas.check_in_schema()},
           required: [:check_in]
         }},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}}
    ]
  )

  def check_in(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    params = %{"location_id" => Map.get(conn.body_params, :location_id)}

    with {:ok, check_in} <-
           CheckInOpenGym.call(conn.assigns.tenant_context, actor, actor.id, params) do
      conn
      |> put_status(:created)
      |> json(%{check_in: check_in})
    end
  end

  defp normalize_body_params(conn, params), do: ParamExtractor.body(%{body_params: conn}, params)

  operation(:check_in_class,
    summary: "Check in to a class you booked (from 30 minutes before it starts until it ends)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Attendance", "application/json",
         %Schema{
           type: :object,
           properties: %{
             attendance: %Schema{
               type: :object,
               properties: %{
                 scheduled_class_id: %Schema{type: :string, format: :uuid},
                 status: %Schema{type: :string},
                 marked_at: %Schema{type: :string, format: :"date-time"}
               },
               required: [:scheduled_class_id, :status, :marked_at]
             }
           },
           required: [:attendance]
         }},
      conflict: {"Outside the check-in window", "application/json", %Schema{type: :object}}
    ]
  )

  def check_in_class(conn, %{id: id}) do
    with {:ok, attendance} <-
           CheckInToClass.call(
             conn.assigns.tenant_context,
             GuardianPlug.current_resource(conn),
             id
           ) do
      json(conn, %{attendance: Map.take(attendance, [:scheduled_class_id, :status, :marked_at])})
    end
  end
end
