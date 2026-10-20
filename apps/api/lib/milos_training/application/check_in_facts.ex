defmodule MilosTraining.Application.CheckInFacts do
  @moduledoc """
  Gathers what `ResolveScan` and `DeskAssessment` decide on (ADR-155), in
  the box's scope: the person's approved bookings around now with their
  attendance, whether they are a member, their open-gym check-in today and
  package coverage, and the box's classes starting soon.
  """

  alias MilosTraining.{Facility, Finance, Organizations, Scheduling}
  alias MilosTraining.Facility.Domain.CheckInPolicy

  @lookbehind_minutes 120
  @lookahead_hours 12
  @classes_ahead_hours 3

  @doc """
  Facts for `user_id` at `location_id`. `opts`: `member?` (skip the lookup
  when the caller knows), `entitlement: true` to include the member's
  effective entitlement (the desk).
  """
  def gather(%{organization_id: organization_id} = context, user_id, location_id, now, opts \\ []) do
    member? =
      Keyword.get_lazy(opts, :member?, fn ->
        Organizations.membership_standing(organization_id, user_id) == :member
      end)

    facts = %{
      location_id: location_id,
      member?: member?,
      bookings: bookings(context, user_id, now),
      classes: classes(context, now),
      open_gym: if(member?, do: open_gym(context, user_id, location_id, now), else: %{})
    }

    if Keyword.get(opts, :entitlement, false),
      do: Map.put(facts, :entitlement, entitlement(context, user_id)),
      else: facts
  end

  defp bookings(context, user_id, now) do
    slots =
      context
      |> Scheduling.list_member_slots(
        user_id,
        DateTime.add(now, -@lookbehind_minutes * 60, :second),
        DateTime.add(now, @lookahead_hours * 3600, :second)
      )
      |> Enum.filter(fn slot ->
        booking = slot.user_booking
        to_string(booking.status) == "approved" and is_nil(booking.guest_name)
      end)

    attendance = Scheduling.list_user_attendance(context, user_id, Enum.map(slots, & &1.id))

    Enum.map(slots, fn slot ->
      %{
        id: slot.user_booking.id,
        kind: slot.user_booking.kind,
        scheduled_class_id: slot.id,
        starts_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        location_id: slot.location_id,
        name: class_name(slot),
        attendance: attendance |> Map.get(slot.id) |> status()
      }
    end)
  end

  defp classes(context, now) do
    context
    |> Scheduling.get_calendar_week(%{
      start_at: DateTime.add(now, -@lookbehind_minutes * 60, :second),
      end_at: DateTime.add(now, @classes_ahead_hours * 3600, :second),
      class_type_ids: []
    })
    |> Enum.map(fn slot ->
      %{
        id: slot.id,
        name: class_name(slot),
        starts_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        location_id: Map.get(slot, :location_id),
        capacity: slot.capacity,
        spots_remaining: Map.get(slot, :spots_remaining)
      }
    end)
  end

  defp open_gym(context, user_id, location_id, now) do
    today = CheckInPolicy.local_date(now, timezone(context))

    request =
      location_id
      |> CheckInPolicy.entitlement_request(today)
      |> Map.put(:starts_at, now)

    %{
      existing: Facility.get_check_in(context, user_id, today),
      covered?: context |> Finance.package_coverage(user_id, [request]) |> List.first() == true
    }
  end

  defp entitlement(context, user_id), do: Finance.get_effective_entitlement(context, user_id)

  defp timezone(context),
    do: context |> Finance.get_finance_settings() |> Map.get(:entitlement_timezone)

  @doc "A class's display name: its type's name, else its own."
  def class_name(slot) do
    case Map.get(slot, :class_type) do
      %{name: name} when is_binary(name) -> name
      _none -> Map.get(slot, :name)
    end
  end

  defp status(nil), do: nil
  defp status(status), do: to_string(status)
end
