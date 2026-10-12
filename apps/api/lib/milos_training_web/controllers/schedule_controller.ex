defmodule MilosTrainingWeb.ScheduleController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetScheduleCalendar
  alias MilosTraining.Application.SubmitBooking
  alias MilosTraining.Application.WithdrawBooking
  alias MilosTrainingWeb.ParamExtractor
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:index, :create_booking]

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
             slots: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:start_date, :end_date, :days, :class_types, :slots]
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
      {:ok, _booking} -> json(conn, %{ok: true})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :booking_not_withdrawable} -> {:error, :unprocessable_entity}
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end

  defp normalize_body_params(conn, params), do: ParamExtractor.body(%{body_params: conn}, params)
end
