defmodule Palee.Application.SubmitBooking do
  require Logger

  alias Palee.Application.{BookingTerms, TrackAnalyticsEvent}
  alias Palee.{Finance, Identity, Scheduling}
  alias Palee.Scheduling.Domain.{BookingOperationPolicy, BookingPolicy}

  @doc """
  Submits a booking request.

  `call/3` keeps the historical `{:ok, booking}` shape. `call/4` accepts
  `client_operation_id:` (ADR-120) and returns `{:ok, booking, :created |
  :replayed}`: a replay of an operation that already created a booking returns
  that booking without reserving another class visit, notifying staff, or
  broadcasting again; reusing the id for another class is
  `{:error, :idempotency_key_conflict}`.
  """
  def call(context, %{id: _} = actor, slot_id) do
    case call(context, actor, slot_id, []) do
      {:ok, booking, _outcome} -> {:ok, booking}
      error -> error
    end
  end

  def call(context, %{id: user_id} = actor, slot_id, opts) when is_list(opts) do
    with {:ok, operation_id} <-
           BookingOperationPolicy.normalize_operation_id(Keyword.get(opts, :client_operation_id)),
         :none <- find_replay(context, user_id, operation_id, slot_id) do
      submit(context, actor, slot_id, operation_id)
    end
  end

  defp submit(context, %{id: user_id} = actor, slot_id, operation_id) do
    now = DateTime.utc_now()

    with {:ok, slot} <- fetch_slot(context, slot_id),
         :ok <- BookingPolicy.can_book?(slot, user_id: user_id, now: now),
         terms = BookingTerms.for_slot(context, user_id, slot),
         :ok <-
           BookingPolicy.booking_window_open?(slot.scheduled_at, now, terms.booking_window_days),
         request = BookingPolicy.entitlement_request(slot),
         {:ok, reservation} <- reserve_visit(context, actor, slot, request) do
      attrs = %{
        entitlement_allowance: BookingPolicy.booking_allowance(request),
        client_operation_id: operation_id
      }

      case create_booking(context, slot, user_id, attrs) do
        {:ok, booking} ->
          dispatch_booking_notification(slot, booking)
          broadcast_booking_event(slot, booking)
          broadcast_entitlement_change(user_id)

          Palee.DomainEvents.publish(:booking_made, %{
            organization_id: slot.organization_id,
            booking_id: booking.id,
            user_id: user_id,
            at: now
          })

          TrackAnalyticsEvent.call("class_booking_requested", context, booking, %{
            user_id: user_id,
            metadata: %{auto_approved: slot.auto_approve == true}
          })

          {:ok, booking, :created}

        {:error, reason} ->
          release_failed_reservation(context, reservation)
          # A concurrent delivery of the same operation may have won the race.
          case find_replay(context, user_id, operation_id, slot_id) do
            :none -> {:error, reason}
            replay_or_conflict -> replay_or_conflict
          end
      end
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, details} -> {:error, reason, details}
    end
  end

  defp find_replay(_context, _user_id, nil, _slot_id), do: :none
  defp find_replay(nil, _user_id, _operation_id, _slot_id), do: :none

  defp find_replay(context, user_id, operation_id, slot_id) do
    case Scheduling.get_booking_by_client_operation(context, user_id, operation_id) do
      nil ->
        :none

      {:error, reason} ->
        {:error, reason}

      booking ->
        case BookingOperationPolicy.submission_replay(booking, slot_id) do
          :replay -> {:ok, booking, :replayed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def call(%{id: _} = actor, slot_id), do: call(nil, actor, slot_id)

  def call(user_id, slot_id) when is_binary(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :not_found}
      actor -> call(nil, actor, slot_id)
    end
  end

  @doc false
  def reserve_visit(context, actor, slot, entitlement_request) do
    request =
      Map.merge(entitlement_request, %{
        actor_role: actor.role,
        starts_at: slot.scheduled_at,
        location_id: Map.get(slot, :location_id),
        source_context: "scheduling",
        source_id: slot.id,
        idempotency_key: "booking-reservation:#{Ecto.UUID.generate()}"
      })

    case context do
      nil -> Finance.reserve_entitlement(actor.id, request)
      context -> Finance.reserve_entitlement(context, actor.id, request)
    end
  end

  @doc false
  def release_failed_reservation(_context, %{id: nil}), do: :ok

  def release_failed_reservation(context, %{id: reservation_id}) do
    params = %{
      reason: "Scheduling rejected booking creation",
      idempotency_key: "booking-compensation:#{reservation_id}"
    }

    case context do
      nil -> Finance.release_entitlement(reservation_id, params)
      context -> Finance.release_entitlement(context, reservation_id, params)
    end

    :ok
  end

  defp broadcast_submission(booking) do
    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "booking:submitted",
      {:booking_submitted, booking}
    )
  end

  defp get_slot(nil, slot_id), do: Scheduling.get_slot(slot_id)
  defp get_slot(context, slot_id), do: Scheduling.get_slot(context, slot_id)

  # `get_slot/2` can return a slot, `nil` (not found), or an `{:error, reason}`
  # tuple (e.g. `:organization_context_required` when no tenant context is
  # available). Normalize all three into a tagged tuple so a failed lookup
  # can never be mistaken for a slot and passed into `BookingPolicy.can_book?/2`.
  defp fetch_slot(context, slot_id) do
    case get_slot(context, slot_id) do
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      slot -> {:ok, slot}
    end
  end

  @doc false
  def create_booking(nil, %{auto_approve: true, id: slot_id}, user_id, _attrs),
    do: Scheduling.submit_auto_approved_booking(user_id, slot_id)

  def create_booking(context, %{auto_approve: true, id: slot_id}, user_id, attrs),
    do: Scheduling.submit_auto_approved_booking_with(context, user_id, slot_id, attrs)

  def create_booking(nil, slot, user_id, _attrs),
    do: Scheduling.submit_booking(user_id, slot.id, slot.booking_timeout_minutes)

  def create_booking(context, slot, user_id, attrs),
    do:
      Scheduling.submit_booking_with(
        context,
        user_id,
        slot.id,
        slot.booking_timeout_minutes,
        attrs
      )

  @doc false
  def dispatch_booking_notification(%{auto_approve: true}, booking),
    do: dispatch_non_critical(:booking_resolved, booking)

  def dispatch_booking_notification(_slot, booking),
    do: dispatch_non_critical(:booking_submitted, booking)

  defp dispatch_non_critical(event, booking) do
    case notification_dispatcher().dispatch_event(event, booking) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "booking_notification_dispatch_failed event=#{event} booking_id=#{booking.id} reason=#{inspect(reason)}"
        )
    end
  rescue
    error ->
      Logger.warning(
        "booking_notification_dispatch_failed event=#{event} booking_id=#{booking.id} reason=#{Exception.message(error)}"
      )
  end

  @doc false
  def broadcast_booking_event(%{auto_approve: true}, booking) do
    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "booking:resolved",
      {:booking_resolved, booking}
    )
  end

  def broadcast_booking_event(_slot, booking), do: broadcast_submission(booking)

  defp notification_dispatcher do
    Application.get_env(:palee, :notification_dispatcher, Palee.Notifications)
  end

  @doc false
  def broadcast_entitlement_change(user_id) do
    Palee.Application.BroadcastUserSync.for_user(user_id, ["finance_entitlement"],
      reason: "class_visit_reserved"
    )
  end
end
