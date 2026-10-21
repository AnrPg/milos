defmodule MilosTraining.Application.CheckInActions do
  @moduledoc """
  The writes behind every QR check-in (ADR-155), shared by the door scan,
  the desk and Wallet: check in to a booked class or to open gym recording
  how it happened, undo a scan within its minute, tell the desk and the door
  display, and summarize what is left on the member's package.

  Live updates go to the staff topic `check_in:<organization_id>`:
  `checked_in` (`location_id`, `first_name`, `kind`, `method`, `at`; first
  names only, for the door's welcome line) and `visitor_scanned` (a person
  who is not a member, for the desk's «Επισκέπτης»).
  """

  alias MilosTraining.Application.{
    AdminRecordAttendance,
    CheckInOpenGym,
    RealtimePublisher,
    TrackAnalyticsEvent
  }

  alias MilosTraining.Application.Trials, as: TrialUseCases

  alias MilosTraining.{
    Facility,
    Finance,
    Identity,
    Notifications,
    Organizations,
    Scheduling,
    Trials
  }

  alias MilosTraining.Trials.TrialRequest

  @undo_seconds 60

  def undo_seconds, do: @undo_seconds
  def topic(organization_id), do: "check_in:#{organization_id}"

  @doc "Checks in to a booked class (`booking` from `CheckInFacts`)."
  def check_in_class(context, booking, actor_id, user_id, method, now) do
    with {:ok, attendance} <-
           Scheduling.record_attendance(context, %{
             scheduled_class_id: booking.scheduled_class_id,
             booking_id: booking.id,
             user_id: user_id,
             status: "attended",
             marked_by_id: actor_id,
             marked_at: now,
             check_in_method: method,
             params: %{"source" => if(actor_id == user_id, do: "self", else: "staff")}
           }) do
      AdminRecordAttendance.announce_attendance(attendance)

      TrackAnalyticsEvent.call("class_attendance_recorded", context, attendance, %{
        metadata: %{member_id: user_id, method: method}
      })

      announce(context, booking.location_id, user_id, "class", method, now)
      {:ok, attendance}
    end
  end

  @doc "Checks in to open gym. `opts`: `defer_finalize`, `override`."
  def check_in_open_gym(context, actor, user_id, location_id, method, now, opts \\ []) do
    params = %{
      "location_id" => location_id,
      "method" => method,
      "defer_finalize" => Keyword.get(opts, :defer_finalize, false),
      "override" => Keyword.get(opts, :override, false)
    }

    with {:ok, check_in} <- CheckInOpenGym.call(context, actor, user_id, params) do
      unless check_in.already_checked_in,
        do: announce(context, location_id, user_id, "open_gym", method, now)

      {:ok, check_in}
    end
  end

  @doc """
  Reverses a scan's check-in within its minute: the attendance or open-gym
  record goes and the open-gym visit returns to the package (a class keeps
  its booking, which holds the class visit). A trial booking's trial goes
  back from attended to `trial_was`, the status it had before the check-in
  (`booked` when unknown).
  """
  def undo(context, kind, id, user_id, now, opts \\ [])

  def undo(context, "class", id, user_id, now, opts) do
    with %{user_id: ^user_id, status: "attended"} = attendance <-
           Scheduling.get_attendance(context, id) || {:error, :not_found},
         :ok <- within_undo(attendance.marked_at, now),
         {:ok, _deleted} <- Scheduling.delete_attendance(context, id) do
      undo_trial_attend(context, attendance.booking_id, Keyword.get(opts, :trial_was))
      broadcast(context, "check_in_undone", %{kind: "class", user_id: user_id, at: now})
      {:ok, %{kind: "class", id: id}}
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end

  def undo(context, "open_gym", id, user_id, now, _opts) do
    with %{user_id: ^user_id} = check_in <-
           Facility.get_check_in_by_id(context, id) || {:error, :not_found},
         :ok <- within_undo(check_in.checked_in_at, now),
         {:ok, _deleted} <- Facility.delete_check_in(context, id) do
      if check_in.reservation_id, do: CheckInOpenGym.release_visit(context, check_in)
      broadcast(context, "check_in_undone", %{kind: "open_gym", user_id: user_id, at: now})
      {:ok, %{kind: "open_gym", id: id}}
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end

  def undo(_context, _kind, _id, _user_id, _now, _opts), do: {:error, :not_found}

  @doc "The status of the trial behind a booking, if the booking is a trial seat."
  def trial_status(_context, nil), do: nil

  def trial_status(%{organization_id: organization_id}, booking_id) do
    case Trials.get_request_by_booking(%{organization_id: organization_id}, booking_id) do
      %TrialRequest{status: status} -> status
      nil -> nil
    end
  end

  defp undo_trial_attend(_context, nil, _trial_was), do: :ok

  defp undo_trial_attend(%{organization_id: organization_id}, booking_id, trial_was) do
    box = %{organization_id: organization_id}
    previous = if trial_was in ["booked", "no_show"], do: trial_was, else: "booked"

    with %TrialRequest{status: "attended"} = request <-
           Trials.get_request_by_booking(box, booking_id),
         {:ok, updated} <- Trials.undo_attend(box, request, previous) do
      TrialUseCases.track_status(box, updated)
    end

    :ok
  end

  defp within_undo(%DateTime{} = at, now) do
    if DateTime.diff(now, at, :second) <= @undo_seconds,
      do: :ok,
      else: {:error, :undo_expired}
  end

  defp within_undo(_at, _now), do: {:error, :undo_expired}

  @doc "Tells the desk and the door display: first name only."
  def announce(context, location_id, user_id, kind, method, now) do
    person = Identity.find_by_id(user_id)

    broadcast(context, "checked_in", %{
      location_id: location_id,
      first_name: first_name(person),
      kind: kind,
      method: method,
      at: now
    })
  end

  @doc "A visitor scanned the door: the desk sees them as «Επισκέπτης»."
  def announce_visitor(context, scan, person) do
    broadcast(context, "visitor_scanned", %{
      id: scan.id,
      location_id: scan.location_id,
      user_id: scan.user_id,
      display_name: display_name(person),
      avatar_url: person && Map.get(person, :avatar_url),
      at: scan.scanned_at
    })
  end

  @visitor_notice_seconds 3600

  @doc """
  Board 10 Q3: staff with `check_in` hear about a person who is not a member
  at the door, so the desk can follow up and sell a walk-in or a trial. At
  most once an hour per person and box (the visitor scans are the record).
  """
  def notify_visitor(context, scan, person, door, trial_available?) do
    since = DateTime.add(scan.scanned_at, -@visitor_notice_seconds, :second)

    earlier? =
      context
      |> Facility.list_visitor_scans(%{from: since, to: scan.scanned_at, limit: 500})
      |> Enum.any?(&(&1.user_id == scan.user_id and &1.id != scan.id))

    if earlier? do
      :ok
    else
      zone = Organizations.organization_timezone(context.organization_id)

      Notifications.dispatch_event(:check_in_visitor, %{
        organization_id: context.organization_id,
        scan_id: scan.id,
        visitor_id: scan.user_id,
        person_nickname: display_name(person),
        box_name: door.name,
        location_name: door.location_name,
        scanned_at: scan.scanned_at,
        scanned_when: scan.scanned_at |> DateTime.shift_zone!(zone) |> Calendar.strftime("%H:%M"),
        trial_available: trial_available?,
        hour: div(DateTime.to_unix(scan.scanned_at), @visitor_notice_seconds),
        url: "/admin/check-in?visitor=" <> scan.id
      })
    end
  end

  defp broadcast(%{organization_id: organization_id}, event, payload) do
    RealtimePublisher.broadcast(topic(organization_id), event, payload)
    :ok
  end

  @doc "The first word of how a person shows their name."
  def first_name(nil), do: nil

  def first_name(person) do
    person
    |> display_name()
    |> to_string()
    |> String.split(~r/[\s_.]+/u, trim: true)
    |> List.first()
  end

  def display_name(nil), do: nil

  def display_name(person),
    do: Map.get(person, :display_nickname) || Map.get(person, :nickname)

  @doc """
  What is left on the member's package: status, package name, end date, the
  class and open-gym visits remaining (nil = unlimited), and a freeze.
  """
  def package_summary(context, user_id) do
    case Finance.get_effective_entitlement(context, user_id) do
      nil -> nil
      entitlement -> present_package(entitlement)
    end
  end

  def present_package(nil), do: nil

  def present_package(entitlement) do
    allowances = Map.get(entitlement, :allowances) || %{}
    subscription = Map.get(entitlement, :subscription) || %{}

    %{
      status: Map.get(entitlement, :status),
      name: Map.get(subscription, :package_name),
      expires_on: Map.get(subscription, :ends_on) || Map.get(entitlement, :expires_on),
      frozen_until: Map.get(entitlement, :frozen_until),
      class_visits_left: left(allowances, :class_visits),
      open_gym_visits_left: left(allowances, :open_gym_visits),
      unlimited:
        Enum.any?([:class_visits, :open_gym_visits], &(left(allowances, &1) == :unlimited))
    }
    |> then(fn package ->
      Map.new(package, fn
        {key, :unlimited} when key != :unlimited -> {key, nil}
        pair -> pair
      end)
    end)
  end

  defp left(allowances, key) do
    case Map.get(allowances, key) do
      %{remaining: remaining} -> remaining
      _none -> nil
    end
  end
end
