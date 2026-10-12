defmodule MilosTrainingWeb.Schemas.Appointments do
  @moduledoc "OpenAPI schemas for appointments (ADR-098)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @date_time %Schema{type: :string, format: :"date-time"}

  def booking_schema do
    %Schema{
      title: "AppointmentBooking",
      type: :object,
      properties: %{
        id: @uuid,
        slot_id: @uuid,
        user_id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string, enum: ["booked", "cancelled", "attended", "no_show"]},
        allowance: %Schema{type: :string, enum: ["pt_sessions", "assessments"]},
        late_cancellation: %Schema{type: :boolean},
        cancelled_at: %Schema{type: :string, format: :"date-time", nullable: true},
        slot: %Schema{type: :object, additionalProperties: true, nullable: true}
      },
      required: [:id, :slot_id, :user_id, :status, :allowance]
    }
  end

  def slot_schema do
    %Schema{
      title: "AppointmentSlot",
      type: :object,
      properties: %{
        id: @uuid,
        coach_id: @uuid,
        kind: %Schema{type: :string, enum: ["pt_session", "assessment"]},
        format: %Schema{type: :string, enum: ["one_to_one", "semi_private"]},
        starts_at: @date_time,
        duration_minutes: %Schema{type: :integer},
        capacity: %Schema{type: :integer},
        spots_remaining: %Schema{type: :integer, nullable: true},
        location_id: @nullable_uuid,
        notes: %Schema{type: :string, nullable: true},
        cancelled_at: %Schema{type: :string, format: :"date-time", nullable: true},
        booked_by_me: %Schema{type: :boolean},
        bookings: %Schema{type: :array, items: booking_schema()}
      },
      required: [:id, :coach_id, :kind, :format, :starts_at, :duration_minutes, :capacity]
    }
  end

  def slot_params_schema do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        coach_id: @nullable_uuid,
        kind: %Schema{type: :string, enum: ["pt_session", "assessment"]},
        format: %Schema{type: :string, enum: ["one_to_one", "semi_private"]},
        starts_at: @date_time,
        duration_minutes: %Schema{type: :integer, minimum: 15, maximum: 240},
        capacity: %Schema{type: :integer, minimum: 1, maximum: 4},
        location_id: @nullable_uuid,
        notes: %Schema{type: :string, maxLength: 1000, nullable: true}
      },
      required: [:kind, :format, :starts_at, :duration_minutes]
    }
  end

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def wrap(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def list(key, schema), do: wrap(key, %Schema{type: :array, items: schema})
end
