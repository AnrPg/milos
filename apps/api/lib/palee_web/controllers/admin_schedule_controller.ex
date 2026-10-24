defmodule PaleeWeb.AdminScheduleController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    AdminRecordAttendance,
    CreateRecurringClassSeries,
    CreateScheduledSlot,
    DeleteScheduledSlot,
    LinkClassWorkout,
    ResolveBooking,
    UpdateScheduledSlot
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :create_slot,
              :create_series,
              :update_slot,
              :link_workout,
              :approve_booking,
              :reject_booking
            ]

  @slot_body_schema %Schema{
    type: :object,
    properties: %{
      # ADR-176: optional. A class without a series and without a WOD is a
      # draft members cannot see until a WOD is linked.
      master_workout_id: %Schema{type: :string, format: :uuid, nullable: true},
      class_type_id: %Schema{type: :string, format: :uuid},
      location_id: %Schema{type: :string, format: :uuid, nullable: true},
      coach_user_id: %Schema{type: :string, format: :uuid, nullable: true},
      name: %Schema{type: :string, minLength: 1, maxLength: 120},
      duration_minutes: %Schema{type: :integer, minimum: 1, maximum: 1440},
      scheduled_at: %Schema{type: :string, format: :"date-time"},
      capacity: %Schema{type: :integer},
      auto_approve: %Schema{type: :boolean},
      booking_timeout_minutes: %Schema{type: :integer}
    },
    required: [
      :class_type_id,
      :scheduled_at,
      :capacity,
      :auto_approve,
      :booking_timeout_minutes
    ]
  }

  # ADR-186 §8: «Ισχύει για» — one class per listed branch, all or none.
  @slot_create_schema %{
    @slot_body_schema
    | properties:
        Map.put(
          @slot_body_schema.properties,
          :location_ids,
          PaleeWeb.Schemas.LocationScope.targets_schema()
        )
  }

  @message_schema %Schema{
    type: :object,
    properties: %{
      admin_message: %Schema{type: :string},
      client_operation_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description:
          "Stable client operation id (ADR-120). Replaying the operation that already " <>
            "resolved the booking returns it with 200 and no new notification."
      }
    },
    required: []
  }

  @resolution_error %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}}
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:create_slot,
    summary: "Create a scheduled class slot (one per branch of location_ids)",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @slot_create_schema}}
    },
    responses: [
      created:
        {"Slot", "application/json",
         %Schema{
           type: :object,
           properties: %{
             slot: %Schema{type: :object, additionalProperties: true},
             slots: %Schema{
               type: :array,
               description: "ADR-186: every class created, one per branch",
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:slot, :slots]
         }}
    ]
  )

  operation(:create_series,
    summary: "Create a recurring class series",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{
              class_type_id: %Schema{type: :string, format: :uuid},
              location_id: %Schema{type: :string, format: :uuid, nullable: true},
              location_ids: PaleeWeb.Schemas.LocationScope.targets_schema(),
              coach_user_id: %Schema{type: :string, format: :uuid, nullable: true},
              master_workout_id: %Schema{type: :string, format: :uuid, nullable: true},
              name: %Schema{type: :string, minLength: 1, maxLength: 120},
              duration_minutes: %Schema{type: :integer, minimum: 1, maximum: 1440},
              timezone: %Schema{type: :string},
              starts_on: %Schema{type: :string, format: :date},
              ends_on: %Schema{type: :string, format: :date, nullable: true},
              local_start_time: %Schema{type: :string, format: :time},
              weekdays: %Schema{
                type: :array,
                minItems: 1,
                uniqueItems: true,
                items: %Schema{type: :integer, minimum: 1, maximum: 7}
              },
              excluded_dates: %Schema{
                type: :array,
                uniqueItems: true,
                items: %Schema{type: :string, format: :date}
              },
              capacity: %Schema{type: :integer, minimum: 1},
              auto_approve: %Schema{type: :boolean},
              booking_timeout_minutes: %Schema{type: :integer, minimum: 1}
            },
            required: [
              :class_type_id,
              :name,
              :duration_minutes,
              :timezone,
              :starts_on,
              :local_start_time,
              :weekdays,
              :capacity,
              :auto_approve,
              :booking_timeout_minutes
            ]
          }
        }
      }
    },
    responses: [
      created:
        {"Batch result", "application/json", %Schema{type: :object, additionalProperties: true}}
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

  operation(:link_workout,
    summary: "Link a WOD to a class",
    description:
      "ADR-176: publishes a draft class (created without a WOD) or completes a series " <>
        "occurrence. The WOD is filed in the day's Classes folder.",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{master_workout_id: %Schema{type: :string, format: :uuid}},
            required: [:master_workout_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Slot", "application/json",
         %Schema{
           type: :object,
           properties: %{slot: %Schema{type: :object, additionalProperties: true}},
           required: [:slot]
         }},
      not_found: {"Class or workout not found", "application/json", @resolution_error}
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
    description:
      "Booking resolution is never replayed blindly (ADR-120): a booking that is no longer " <>
        "pending returns 409 `booking_not_pending` unless it was resolved by this same " <>
        "`client_operation_id`, which returns the booking with 200.",
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
         }},
      not_found: {"Booking not found", "application/json", @resolution_error},
      conflict:
        {"Booking no longer pending, slot full, or operation id conflict", "application/json",
         @resolution_error},
      unprocessable_entity: {"Invalid request", "application/json", @resolution_error}
    ]
  )

  operation(:reject_booking,
    summary: "Reject a booking",
    description:
      "Booking resolution is never replayed blindly (ADR-120): a booking that is no longer " <>
        "pending returns 409 `booking_not_pending` unless it was resolved by this same " <>
        "`client_operation_id`, which returns the booking with 200.",
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
         }},
      not_found: {"Booking not found", "application/json", @resolution_error},
      conflict:
        {"Booking no longer pending, slot full, or operation id conflict", "application/json",
         @resolution_error},
      unprocessable_entity: {"Invalid request", "application/json", @resolution_error}
    ]
  )

  def create_slot(conn, params) do
    body = normalize_body_params(conn, params)

    with :ok <- valid_coach(conn.assigns.tenant_context, body),
         {:ok, [slot | _] = slots} <-
           CreateScheduledSlot.call_at_branches(conn.assigns.tenant_context, body) do
      conn
      |> put_status(:created)
      |> json(%{slot: slot, slots: slots})
    end
  end

  def create_series(conn, params) do
    body = normalize_body_params(conn, params)

    with :ok <- valid_coach(conn.assigns.tenant_context, body),
         {:ok, [series | _] = all} <-
           CreateRecurringClassSeries.call_at_branches(conn.assigns.tenant_context, body) do
      conn |> put_status(:created) |> json(%{series: series, series_list: all})
    end
  end

  def update_slot(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with :ok <- valid_coach(conn.assigns.tenant_context, body),
         {:ok, slot} <- UpdateScheduledSlot.call(conn.assigns.tenant_context, id, body) do
      json(conn, %{slot: slot})
    end
  end

  def link_workout(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)
    workout_id = body["master_workout_id"] || body[:master_workout_id]

    with {:ok, slot} <- LinkClassWorkout.call(conn.assigns.tenant_context, id, workout_id) do
      json(conn, %{slot: slot})
    end
  end

  # A class's coach must be a coach of this gym (ADR-100).
  defp valid_coach(context, body) do
    case body["coach_user_id"] || body[:coach_user_id] do
      coach_id when is_binary(coach_id) and coach_id != "" ->
        if :coach in Palee.Organizations.member_roles(context.organization_id, coach_id),
          do: :ok,
          else: {:error, :not_a_coach}

      _none ->
        :ok
    end
  end

  def delete_slot(conn, %{"id" => id}) do
    with :ok <- DeleteScheduledSlot.call(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  def approve_booking(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with {:ok, booking, _outcome} <-
           ResolveBooking.call(conn.assigns.tenant_context, id, %{
             action: :approve,
             admin_message: body["admin_message"] || body[:admin_message],
             client_operation_id: body["client_operation_id"] || body[:client_operation_id]
           }) do
      json(conn, %{booking: booking})
    end
  end

  def reject_booking(conn, params) do
    id = params["id"] || params[:id]
    body = normalize_body_params(conn, params)

    with {:ok, booking, _outcome} <-
           ResolveBooking.call(conn.assigns.tenant_context, id, %{
             action: :reject,
             admin_message: body["admin_message"] || body[:admin_message],
             client_operation_id: body["client_operation_id"] || body[:client_operation_id]
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
    slot_id = params["slot_id"] || params[:slot_id]
    user_id = params["user_id"] || params[:user_id]
    # ADR-198: the signed-in staff member; no plug assigns `:current_user`.
    admin_id = Guardian.Plug.current_resource(conn).id
    body = normalize_body_params(conn, params)

    with {:ok, attendance} <-
           AdminRecordAttendance.call(
             conn.assigns.tenant_context,
             slot_id,
             user_id,
             admin_id,
             body
           ) do
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
