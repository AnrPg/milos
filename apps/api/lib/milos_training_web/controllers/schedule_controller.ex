defmodule MilosTrainingWeb.ScheduleController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.GetScheduleCalendar
  alias MilosTraining.Application.SubmitBooking
  alias MilosTraining.Application.WithdrawBooking
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create_booking]

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

  @type_param %Parameter{
    name: :training_type,
    in: :query,
    description: "Optional training type filter",
    required: false,
    schema: %Schema{
      type: :string,
      enum: Enum.map(MilosTraining.Scheduling.ScheduledClass.training_types(), &to_string/1)
    }
  }

  operation(:index,
    summary: "Get the schedule window",
    parameters: [@date_param, @start_at_param, @end_at_param, @days_param, @type_param],
    responses: [
      ok:
        {"Schedule", "application/json",
         %Schema{
           type: :object,
           properties: %{
             start_date: %Schema{type: :string, format: :date},
             end_date: %Schema{type: :string, format: :date},
             days: %Schema{type: :integer},
             slots: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:start_date, :end_date, :days, :slots]
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

    with {:ok, payload} <- GetScheduleCalendar.call(actor, params) do
      json(conn, payload)
    end
  end

  def create_booking(conn, %{"slot_id" => slot_id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, booking} <- SubmitBooking.call(actor.id, slot_id) do
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

    case WithdrawBooking.call(actor.id, booking_id) do
      {:ok, _booking} -> json(conn, %{ok: true})
      {:error, :not_found} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :booking_not_withdrawable} -> {:error, :unprocessable_entity}
      {:error, _} -> {:error, :unprocessable_entity}
    end
  end

  defp normalize_body_params(%{} = body_params, _params) when map_size(body_params) > 0,
    do: body_params

  defp normalize_body_params(_, params),
    do: Map.get(params, "body") || Map.get(params, :body) || params
end
