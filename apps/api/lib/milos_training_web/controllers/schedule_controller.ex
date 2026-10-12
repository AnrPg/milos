defmodule MilosTrainingWeb.ScheduleController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    CheckInOpenGym,
    GetScheduleCalendar,
    JoinClassWaitlist,
    SubmitBooking,
    SubmitGuestBooking,
    WithdrawBooking
  }

  alias MilosTraining.Facility
  alias MilosTrainingWeb.ParamExtractor
  alias MilosTrainingWeb.Schemas.Facility, as: FacilitySchemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:index, :create_booking, :join_waitlist, :create_guest_booking, :check_in]

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
    schema: %Schema{type: :integer, enum: [3, 7, 30]}
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
             slots: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:start_date, :end_date, :days, :class_types, :slots]
         }}
    ]
  )

  operation(:create_booking,
    summary: "Book a schedule slot",
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
      created:
        {"Booking", "application/json",
         %Schema{
           type: :object,
           properties: %{booking: %Schema{type: :object, additionalProperties: true}},
           required: [:booking]
         }},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetScheduleCalendar.call(conn.assigns.tenant_context, actor, params) do
      json(conn, payload)
    end
  end

  def create_booking(conn, %{"slot_id" => slot_id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, booking} <- SubmitBooking.call(conn.assigns.tenant_context, actor, slot_id) do
      conn
      |> put_status(:created)
      |> json(%{booking: booking})
    end
  end

  def create_booking(conn, params) do
    body = conn.body_params |> normalize_body_params(params)
    create_booking(conn, %{"slot_id" => body["slot_id"] || body[:slot_id]})
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
    %{slot_id: slot_id} = conn.body_params

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
    %{slot_id: slot_id, guest_name: guest_name} = conn.body_params

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
    params = %{"location_id" => Map.get(conn.body_params || %{}, :location_id)}

    with {:ok, check_in} <-
           CheckInOpenGym.call(conn.assigns.tenant_context, actor, actor.id, params) do
      conn
      |> put_status(:created)
      |> json(%{check_in: check_in})
    end
  end

  defp normalize_body_params(conn, params), do: ParamExtractor.body(%{body_params: conn}, params)
end
