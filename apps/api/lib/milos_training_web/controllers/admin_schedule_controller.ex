defmodule MilosTrainingWeb.AdminScheduleController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    AdminRecordAttendance,
    CreateScheduledSlot,
    DeleteScheduledSlot,
    ResolveBooking,
    UpdateScheduledSlot
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create_slot, :update_slot, :approve_booking, :reject_booking]

  @slot_body_schema %Schema{
    type: :object,
    properties: %{
      master_workout_id: %Schema{type: :string, format: :uuid},
      class_type_id: %Schema{type: :string, format: :uuid},
      scheduled_at: %Schema{type: :string, format: :"date-time"},
      capacity: %Schema{type: :integer},
      auto_approve: %Schema{type: :boolean},
      booking_timeout_minutes: %Schema{type: :integer}
    },
    required: [
      :master_workout_id,
      :class_type_id,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ]
  }

  @message_schema %Schema{
    type: :object,
    properties: %{admin_message: %Schema{type: :string}},
    required: []
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:create_slot,
    summary: "Create a scheduled class slot",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @slot_body_schema}}
    },
    responses: [
      created:
        {"Slot", "application/json",
         %Schema{
           type: :object,
           properties: %{slot: %Schema{type: :object, additionalProperties: true}},
           required: [:slot]
         }}
    ]
  )

  operation(:update_slot,
    summary: "Update a scheduled class slot",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @slot_body_schema}}
    },
    responses: [
      ok:
        {"Slot", "application/json",
         %Schema{
           type: :object,
           properties: %{slot: %Schema{type: :object, additionalProperties: true}},
           required: [:slot]
         }}
    ]
  )

  operation(:delete_slot,
    summary: "Delete a scheduled class slot",
    parameters: [@id_param],
    responses: [
      no_content: {"Deleted", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:approve_booking,
    summary: "Approve a booking",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: @message_schema}}
    },
    responses: [
      ok:
        {"Booking", "application/json",
         %Schema{
           type: :object,
           properties: %{booking: %Schema{type: :object, additionalProperties: true}},
           required: [:booking]
         }}
    ]
  )

  operation(:reject_booking,
    summary: "Reject a booking",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: @message_schema}}
    },
    responses: [
      ok:
        {"Booking", "application/json",
         %Schema{
           type: :object,
           properties: %{booking: %Schema{type: :object, additionalProperties: true}},
           required: [:booking]
         }}
    ]
  )

  def create_slot(conn, params) do
    body = normalize_body_params(conn, params)

    with {:ok, slot} <- CreateScheduledSlot.call(body) do
      conn
      |> put_status(:created)
      |> json(%{slot: slot})
    end
  end

  def update_slot(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with {:ok, slot} <- UpdateScheduledSlot.call(id, body) do
      json(conn, %{slot: slot})
    end
  end

  def delete_slot(conn, %{"id" => id}) do
    with :ok <- DeleteScheduledSlot.call(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def approve_booking(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with {:ok, booking} <-
           ResolveBooking.call(id, %{
             action: :approve,
             admin_message: body["admin_message"] || body[:admin_message]
           }) do
      json(conn, %{booking: booking})
    end
  end

  def reject_booking(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with {:ok, booking} <-
           ResolveBooking.call(id, %{
             action: :reject,
             admin_message: body["admin_message"] || body[:admin_message]
           }) do
      json(conn, %{booking: booking})
    end
  end

  operation(:record_attendance,
    summary: "Record attendance for a user in a class slot",
    parameters: [
      %Parameter{
        name: :slot_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              status: %Schema{
                type: :string,
                enum: ["attended", "missed", "no_show", "late_cancel"]
              },
              notes: %Schema{type: :string, nullable: true}
            }
          }
        }
      }
    },
    responses: [
      ok:
        {"Attendance record", "application/json",
         %Schema{
           type: :object,
           properties: %{attendance: %Schema{type: :object, additionalProperties: true}},
           required: [:attendance]
         }}
    ]
  )

  def record_attendance(conn, params) do
    slot_id = params["slot_id"]
    user_id = params["user_id"]
    admin_id = conn.assigns[:current_user].id
    body = normalize_body_params(conn, params)

    with {:ok, attendance} <- AdminRecordAttendance.call(slot_id, user_id, admin_id, body) do
      json(conn, %{attendance: attendance})
    end
  end

  defp normalize_body_params(conn, params) do
    case conn.body_params do
      %{} = body_params when map_size(body_params) > 0 -> body_params
      _ -> Map.get(params, "body") || Map.get(params, :body) || params
    end
  end
end
