defmodule MilosTrainingWeb.AppointmentsController do
  @moduledoc "Appointments (ADR-098): client booking and staff slot management."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    BookAppointment,
    CancelAppointment,
    CancelAppointmentSlot,
    CreateAppointmentSlot,
    ListOfferedAppointmentSlots,
    RecordAppointmentAttendance
  }

  alias MilosTraining.{Appointments, Organizations}
  alias MilosTrainingWeb.Schemas.Appointments, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Appointments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @booking_response S.wrap(:appointment, S.booking_schema())
  @slot_response S.wrap(:slot, S.slot_schema())

  # Client

  operation(:offered_slots,
    summary: "Upcoming appointment slots I can book with my packages",
    responses: [ok: {"Slots", "application/json", S.list(:slots, S.slot_schema())}]
  )

  def offered_slots(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    json(conn, %{slots: ListOfferedAppointmentSlots.call(conn.assigns.tenant_context, actor)})
  end

  operation(:my_appointments,
    summary: "My appointments",
    responses: [
      ok: {"Appointments", "application/json", S.list(:appointments, S.booking_schema())}
    ]
  )

  def my_appointments(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    json(conn, %{
      appointments: Appointments.list_bookings(conn.assigns.tenant_context, %{user_id: actor.id})
    })
  end

  operation(:book,
    summary: "Book an appointment slot",
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{slot_id: %Schema{type: :string, format: :uuid}},
        required: [:slot_id]
      }),
    responses: [
      created: {"Appointment", "application/json", @booking_response},
      forbidden: {"Not included in the package", "application/json", @error},
      conflict: {"Full, used up or already booked", "application/json", @error}
    ]
  )

  def book(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    slot_id = Map.get(conn.body_params, :slot_id)

    with {:ok, booking} <- BookAppointment.call(conn.assigns.tenant_context, actor, slot_id) do
      conn |> put_status(:created) |> json(%{appointment: booking})
    end
  end

  operation(:cancel,
    summary: "Cancel an appointment; inside the cancellation cutoff the session is used",
    parameters: [@id],
    responses: [
      ok: {"Appointment", "application/json", @booking_response},
      conflict: {"No longer active", "application/json", @error}
    ]
  )

  def cancel(conn, %{id: id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, booking} <- CancelAppointment.call(conn.assigns.tenant_context, actor, id) do
      json(conn, %{appointment: booking})
    end
  end

  # Staff

  operation(:slots,
    summary: "Appointment slots in a date range, with their bookings",
    parameters: [
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time"}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time"}
      },
      %Parameter{
        name: :coach_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Slots", "application/json", S.list(:slots, S.slot_schema())}]
  )

  def slots(conn, params) do
    context = conn.assigns.tenant_context

    filters = %{
      from: Map.get(params, :from, DateTime.add(DateTime.utc_now(), -86_400)),
      to: Map.get(params, :to),
      coach_id:
        if(own_slots_only?(context), do: context.user_id, else: Map.get(params, :coach_id))
    }

    json(conn, %{slots: Appointments.list_slots(context, filters)})
  end

  operation(:create_slot,
    summary: "Publish an appointment slot (for yourself or another coach)",
    request_body: S.body(S.slot_params_schema()),
    responses: [
      created: {"Slot", "application/json", @slot_response},
      unprocessable_entity: {"Invalid slot", "application/json", @error}
    ]
  )

  def create_slot(conn, _params) do
    staff = GuardianPlug.current_resource(conn)
    coach_id = Map.get(conn.body_params, :coach_id)

    with :ok <- own_coach(conn.assigns.tenant_context, coach_id || staff.id),
         {:ok, slot} <-
           CreateAppointmentSlot.call(conn.assigns.tenant_context, staff, conn.body_params) do
      conn |> put_status(:created) |> json(%{slot: slot})
    end
  end

  operation(:cancel_slot,
    summary: "Cancel a slot; booked clients get their session back",
    parameters: [@id],
    responses: [ok: {"Slot", "application/json", @slot_response}]
  )

  def cancel_slot(conn, %{id: id}) do
    staff = GuardianPlug.current_resource(conn)

    with :ok <- own_slot(conn.assigns.tenant_context, id),
         {:ok, slot} <- CancelAppointmentSlot.call(conn.assigns.tenant_context, staff, id) do
      json(conn, %{slot: slot})
    end
  end

  operation(:book_for_client,
    summary: "Book a client into a slot on their package",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{user_id: %Schema{type: :string, format: :uuid}},
        required: [:user_id]
      }),
    responses: [
      created: {"Appointment", "application/json", @booking_response},
      forbidden: {"Not included in the client's package", "application/json", @error}
    ]
  )

  def book_for_client(conn, %{id: slot_id}) do
    staff = GuardianPlug.current_resource(conn)
    user_id = Map.get(conn.body_params, :user_id)

    with :ok <- own_slot(conn.assigns.tenant_context, slot_id),
         {:ok, booking} <-
           BookAppointment.call(conn.assigns.tenant_context, staff, slot_id, user_id) do
      conn |> put_status(:created) |> json(%{appointment: booking})
    end
  end

  operation(:attendance,
    summary: "Mark an appointment attended or missed",
    parameters: [@id],
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{status: %Schema{type: :string, enum: ["attended", "no_show"]}},
        required: [:status]
      }),
    responses: [
      ok: {"Appointment", "application/json", @booking_response},
      conflict: {"No longer active", "application/json", @error}
    ]
  )

  def attendance(conn, %{id: id}) do
    staff = GuardianPlug.current_resource(conn)
    status = Map.get(conn.body_params, :status)

    with :ok <- own_booking(conn.assigns.tenant_context, id),
         {:ok, booking} <-
           RecordAppointmentAttendance.call(conn.assigns.tenant_context, staff, id, status) do
      json(conn, %{appointment: booking})
    end
  end

  # A coach with scope `:own` manages only their own slots (ADR-100); front
  # desk and managers reach every slot.
  defp own_slots_only?(context) do
    Organizations.capability_scope(context, :manage_appointments) == :own and
      not Organizations.can?(context, :book_for_clients)
  end

  defp own_coach(context, coach_id) do
    if own_slots_only?(context) and coach_id != context.user_id,
      do: {:error, :forbidden},
      else: :ok
  end

  defp own_slot(context, slot_id) do
    if own_slots_only?(context) do
      case Appointments.get_slot(context, slot_id) do
        nil -> {:error, :not_found}
        slot -> own_coach(context, slot.coach_id)
      end
    else
      :ok
    end
  end

  defp own_booking(context, booking_id) do
    if own_slots_only?(context) do
      case Appointments.get_booking(context, booking_id) do
        nil -> {:error, :not_found}
        booking -> own_coach(context, booking.slot.coach_id)
      end
    else
      :ok
    end
  end
end
