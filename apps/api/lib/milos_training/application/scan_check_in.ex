defmodule MilosTraining.Application.ScanCheckIn do
  @moduledoc """
  The door scan (ADR-155, decisions 2–3; vision §7.5): a signed-in person
  opens `/c/<location>/<code>` with the phone camera and the app posts the
  location and code here.

  The code proves presence at the door (`DoorCode`, ±1 window). `ResolveScan`
  decides; this service gathers its facts and carries the decision out:

    * `checked_in` - a booking in the window, or open gym: the check-in, an
      `undo_token` good for one minute, and what is left on the package;
    * `choose` - several bookings in the window: the client posts again with
      `scan_token` (proof of this scan for #{180} s) and `booking_id`;
    * `already_checked_in` - scanning twice changes nothing;
    * `nothing` - a member with nothing to check in to: classes starting soon
      here with a spot («Κλείσε θέση»), their next booking, the package;
    * `visitor` - not a member: the box, the trial classes of today and
      tomorrow at this location (when the owner offers them at the door and
      trials are on), and whether they follow the box. The scan is kept for
      the desk («Επισκέπτης») and staff with `check_in` are notified (at most
      once an hour per person) so the desk can follow up;
    * `no_booking` - a scan of the printed poster by a member with no
      booking in its window.

  The printed poster (`poster_code`, board 10 Q1 extra) is a static code, so
  it only checks in a booking already in its window (method `door_poster`);
  never open gym, suggestions or a trial offer. It works only while the
  owner has it on for the location.

  ADR-173 adds two more static sources with the same rule: an NFC door tag
  (`nfc_code`, method `door_nfc`, while the owner has the tag on) and the
  store app's arrival reminder (`geofence_token` from
  `CheckInGeofences`, method `geofence`, while the box allows reminders).
  A reminder tapped by someone who is no longer a member records nothing:
  the door, not the reminder, is where a visitor is welcomed.
  """

  alias MilosTraining.Application.{
    CheckInActions,
    CheckInFacts,
    CheckInGeofences,
    CheckInKeys,
    SignedToken,
    Trials
  }

  alias MilosTraining.{Community, Facility, Identity, Organizations, Scheduling}
  alias MilosTraining.Facility.Domain.{DoorCode, ResolveScan}

  @scan_salt "check-in-scan-v1"
  @undo_salt "check-in-undo-v1"
  @scan_token_seconds 180

  @doc """
  `params`: `location_id` + `code` (the door) or `poster_code` (the printed
  poster), or `scan_token` (from a `choose` answer); optional `booking_id`.
  """
  def scan(%{id: user_id} = user, params, now \\ DateTime.utc_now()) do
    with {:ok, door} <- door(user_id, params, now) do
      context = %{organization_id: door.organization_id, user_id: user_id}
      rules = Facility.check_in_rules(context)

      facts =
        context
        |> CheckInFacts.gather(user_id, door.location_id, now)
        |> Map.put(:source, door.source)

      booking_id = blank_to_nil(param(params, :booking_id))

      facts
      |> ResolveScan.decide(rules, now, booking_id)
      |> carry_out(context, user, door, facts, now)
    end
  end

  @doc "Undoes a scan's check-in within its minute (`undo_token` from `checked_in`)."
  def undo(%{id: user_id}, token, now \\ DateTime.utc_now()) do
    case SignedToken.verify(@undo_salt, token, max_age: CheckInActions.undo_seconds() + 5) do
      {:ok, %{"o" => organization_id, "k" => kind, "i" => id, "u" => ^user_id} = payload} ->
        context = %{organization_id: organization_id, user_id: user_id}

        with {:ok, undone} <-
               CheckInActions.undo(context, kind, id, user_id, now, trial_was: payload["t"]) do
          {:ok, Map.put(undone, :package, CheckInActions.package_summary(context, user_id))}
        end

      {:ok, _other_person} ->
        {:error, :not_found}

      {:error, :expired} ->
        {:error, :undo_expired}

      {:error, _invalid} ->
        {:error, :invalid_undo_token}
    end
  end

  # -- the door

  defp door(user_id, params, now) do
    cond do
      token = blank_to_nil(param(params, :scan_token)) ->
        verify_scan_token(token, user_id)

      poster = blank_to_nil(param(params, :poster_code)) ->
        verify_poster(param(params, :location_id), poster)

      nfc = blank_to_nil(param(params, :nfc_code)) ->
        verify_nfc(param(params, :location_id), nfc)

      geofence = blank_to_nil(param(params, :geofence_token)) ->
        verify_geofence(geofence, user_id)

      true ->
        verify_door(param(params, :location_id), param(params, :code), now)
    end
  end

  defp verify_poster(location_id, code) when is_binary(location_id) and is_binary(code) do
    with {:ok, location_id} <- Ecto.UUID.cast(location_id),
         %{} = door <- Facility.door_location(location_id),
         context = %{organization_id: door.organization_id},
         {:ok, key, %{enabled: true}} <- CheckInKeys.poster_key(context, location_id),
         :ok <- DoorCode.verify_poster(key, location_id, code) do
      {:ok, Map.put(door, :source, :poster)}
    else
      _invalid -> {:error, :invalid_door_code}
    end
  end

  defp verify_poster(_location_id, _code), do: {:error, :invalid_door_code}

  defp verify_nfc(location_id, code) when is_binary(location_id) and is_binary(code) do
    with {:ok, location_id} <- Ecto.UUID.cast(location_id),
         %{} = door <- Facility.door_location(location_id),
         context = %{organization_id: door.organization_id},
         {:ok, key, %{enabled: true}} <- CheckInKeys.nfc_key(context, location_id),
         :ok <- DoorCode.verify_nfc(key, location_id, code) do
      {:ok, Map.put(door, :source, :nfc)}
    else
      _invalid -> {:error, :invalid_door_code}
    end
  end

  defp verify_nfc(_location_id, _code), do: {:error, :invalid_door_code}

  defp verify_geofence(token, user_id) do
    with {:ok, %{"l" => location_id, "u" => ^user_id}} <-
           SignedToken.verify(CheckInGeofences.token_salt(), token,
             max_age: CheckInGeofences.token_max_age()
           ),
         %{} = door <- Facility.door_location(location_id),
         %{geofence_reminder: true} <-
           Facility.check_in_rules(%{organization_id: door.organization_id}) do
      {:ok, Map.put(door, :source, :geofence)}
    else
      _invalid -> {:error, :invalid_door_code}
    end
  end

  defp verify_door(location_id, code, now) when is_binary(location_id) and is_binary(code) do
    with {:ok, location_id} <- Ecto.UUID.cast(location_id),
         %{} = door <- Facility.door_location(location_id),
         context = %{organization_id: door.organization_id},
         rules = Facility.check_in_rules(context),
         {:ok, key} <- CheckInKeys.door_key(context, location_id),
         :ok <- DoorCode.verify(key, location_id, code, now, rules.door_rotation_seconds) do
      {:ok, Map.put(door, :source, :door)}
    else
      _invalid -> {:error, :invalid_door_code}
    end
  end

  defp verify_door(_location_id, _code, _now), do: {:error, :invalid_door_code}

  defp verify_scan_token(token, user_id) do
    with {:ok, %{"l" => location_id, "u" => ^user_id} = claims} <-
           SignedToken.verify(@scan_salt, token, max_age: @scan_token_seconds),
         %{} = door <- Facility.door_location(location_id) do
      {:ok, Map.put(door, :source, scan_token_source(claims["s"]))}
    else
      _invalid -> {:error, :invalid_scan_token}
    end
  end

  defp scan_token_source("poster"), do: :poster
  defp scan_token_source("nfc"), do: :nfc
  defp scan_token_source("geofence"), do: :geofence
  defp scan_token_source(_door), do: :door

  defp scan_token(door, user_id),
    do:
      SignedToken.sign(@scan_salt, %{
        "l" => door.location_id,
        "u" => user_id,
        "s" => Atom.to_string(door.source)
      })

  defp method(%{source: :poster}), do: "door_poster"
  defp method(%{source: :nfc}), do: "door_nfc"
  defp method(%{source: :geofence}), do: "geofence"
  defp method(_door), do: "door_qr"

  # -- the decision

  defp carry_out({:check_in_class, booking}, context, user, door, _facts, now) do
    # A trial seat's check-in marks the trial attended; the undo puts it back.
    trial_was = CheckInActions.trial_status(context, booking.id)

    with {:ok, attendance} <-
           CheckInActions.check_in_class(context, booking, user.id, user.id, method(door), now) do
      checked_in(context, user, door, class_check_in(attendance, booking), now, trial_was)
    end
  end

  defp carry_out(:open_gym, context, user, door, facts, now) do
    case CheckInActions.check_in_open_gym(
           context,
           user,
           user.id,
           door.location_id,
           method(door),
           now,
           defer_finalize: true
         ) do
      {:ok, %{already_checked_in: true} = check_in} ->
        already(context, user, door, open_gym_check_in(check_in))

      {:ok, check_in} ->
        checked_in(context, user, door, open_gym_check_in(check_in), now, nil)

      # The package said no (no visits left, outside its hours…): the member
      # has nothing to check in to, with the reason.
      {:error, reason, _details} ->
        nothing(context, user, door, facts, now, reason)

      {:error, reason} when is_atom(reason) ->
        if finance_reason?(reason),
          do: nothing(context, user, door, facts, now, reason),
          else: {:error, reason}
    end
  end

  defp carry_out({:choose, bookings}, _context, user, door, _facts, _now) do
    {:ok,
     %{
       outcome: "choose",
       box: present_box(door),
       location: present_location(door),
       choices: Enum.map(bookings, &present_booking/1),
       scan_token: scan_token(door, user.id)
     }}
  end

  defp carry_out({:already_checked_in, {:class, booking}}, context, user, door, _facts, _now) do
    attendance =
      Scheduling.get_attendance_for_user_class(context, user.id, booking.scheduled_class_id)

    already(context, user, door, class_check_in(attendance, booking))
  end

  defp carry_out({:already_checked_in, {:open_gym, check_in}}, context, user, door, _facts, _now),
    do: already(context, user, door, open_gym_check_in(check_in))

  defp carry_out({:nothing, _details}, context, user, door, facts, now),
    do: nothing(context, user, door, facts, now, nil)

  defp carry_out(:visitor, context, user, door, _facts, now),
    do: visitor(context, user, door, now)

  defp carry_out({:poster_no_booking, :visitor}, context, user, door, _facts, _now)
       when door.source == :geofence,
       do: no_booking(context, user, door)

  defp carry_out({:poster_no_booking, :visitor}, context, user, door, _facts, now),
    do: visitor(context, user, door, now)

  defp carry_out({:poster_no_booking, :member}, context, user, door, _facts, _now) do
    {:ok,
     %{
       outcome: "no_booking",
       box: present_box(door),
       location: present_location(door),
       membership: "member",
       package: CheckInActions.package_summary(context, user.id)
     }}
  end

  defp carry_out({:error, reason}, _context, _user, _door, _facts, _now), do: {:error, reason}

  # A reminder tapped after the membership ended: nothing to record.
  defp no_booking(context, user, door) do
    {:ok,
     %{
       outcome: "no_booking",
       box: present_box(door),
       location: present_location(door),
       membership: to_string(Organizations.membership_standing(context.organization_id, user.id))
     }}
  end

  defp checked_in(context, user, door, check_in, now, trial_was) do
    payload = %{
      "o" => context.organization_id,
      "k" => check_in.kind,
      "i" => check_in.id,
      "u" => user.id
    }

    undo_token =
      SignedToken.sign(
        @undo_salt,
        if(trial_was, do: Map.put(payload, "t", trial_was), else: payload)
      )

    {:ok,
     %{
       outcome: "checked_in",
       box: present_box(door),
       location: present_location(door),
       check_in: check_in,
       undo_token: undo_token,
       undo_until: DateTime.add(now, CheckInActions.undo_seconds(), :second),
       package: CheckInActions.package_summary(context, user.id)
     }}
  end

  defp already(context, user, door, check_in) do
    {:ok,
     %{
       outcome: "already_checked_in",
       box: present_box(door),
       location: present_location(door),
       check_in: check_in,
       package: CheckInActions.package_summary(context, user.id)
     }}
  end

  defp nothing(context, user, door, facts, now, reason) do
    {:ok,
     %{
       outcome: "nothing",
       box: present_box(door),
       location: present_location(door),
       reason: reason && to_string(reason),
       classes: facts |> ResolveScan.suggestions(now) |> Enum.map(&present_class/1),
       next_booking:
         case next_booking(facts, now) do
           nil -> nil
           booking -> present_booking(booking)
         end,
       package: CheckInActions.package_summary(context, user.id)
     }}
  end

  defp visitor(context, user, door, now) do
    rules = Facility.check_in_rules(context)

    # The poster offers nothing beyond «not a member».
    trial =
      if rules.visitor_trial_offer and door.source == :door,
        do: trial_offer(context, user, door, now)

    {:ok, scan} =
      Facility.record_visitor_scan(context, %{
        location_id: door.location_id,
        user_id: user.id,
        scanned_at: now,
        trial_offered: trial != nil and trial.enabled
      })

    person = Identity.find_by_id(user.id)
    CheckInActions.announce_visitor(context, scan, person)

    CheckInActions.notify_visitor(
      context,
      scan,
      person,
      door,
      trial_available?(trial) or trials_open?(context)
    )

    {:ok,
     %{
       outcome: "visitor",
       box: present_box(door),
       location: present_location(door),
       membership: to_string(Organizations.membership_standing(context.organization_id, user.id)),
       trial: trial,
       follow: Community.follow_status(%{user_id: user.id}, "organization", door.organization_id)
     }}
  end

  # Trials are asked for on the box's public page, so the door offers them
  # only for a published box, with its trial policy on.
  defp trial_offer(context, user, door, now) do
    with %{} <- Organizations.public_box_by_slug(door.slug),
         zone = Organizations.organization_timezone(context.organization_id),
         {from, to} = today_and_tomorrow(now, zone),
         slots =
           context
           |> Scheduling.get_calendar_week(%{start_at: from, end_at: to, class_type_ids: []})
           |> Enum.filter(&(Map.get(&1, :location_id) in [nil, door.location_id])),
         %{} = offer <- Trials.offer(context.organization_id, user.id, slots, now) do
      classes =
        slots
        |> Enum.filter(&((Map.get(offer.seats, &1.id) || 0) > 0))
        |> Enum.map(fn slot ->
          slot
          |> slot_fact()
          |> present_class()
          |> Map.put(:trial_seats, Map.get(offer.seats, slot.id))
        end)

      offer |> Map.delete(:seats) |> Map.put(:classes, classes)
    else
      _no_offer -> nil
    end
  end

  defp trial_available?(%{enabled: true, classes: [_ | _]}), do: true
  defp trial_available?(_trial), do: false

  # Whether the box takes trials at all, for the staff notice: the desk can
  # offer one even when the door didn't show any.
  defp trials_open?(context), do: MilosTraining.Trials.policy(context).enabled == true

  defp today_and_tomorrow(now, zone) do
    local = DateTime.shift_zone!(now, zone)
    day_after = Date.add(DateTime.to_date(local), 2)

    end_at =
      case DateTime.new(day_after, ~T[00:00:00], zone) do
        {:ok, at} -> at
        {:ambiguous, first, _second} -> first
        {:gap, _before, later} -> later
      end

    {now, DateTime.shift_zone!(end_at, "Etc/UTC")}
  end

  defp next_booking(facts, now) do
    facts.bookings
    |> Enum.filter(&(DateTime.compare(&1.starts_at, now) == :gt))
    |> Enum.min_by(& &1.starts_at, DateTime, fn -> nil end)
  end

  # -- presenting

  defp class_check_in(attendance, booking) do
    %{
      kind: "class",
      id: attendance && attendance.id,
      at: attendance && attendance.marked_at,
      method: attendance && Map.get(attendance, :check_in_method),
      booking: present_booking(booking)
    }
  end

  defp open_gym_check_in(check_in) do
    %{
      kind: "open_gym",
      id: check_in.id,
      at: check_in.checked_in_at,
      method: Map.get(check_in, :method),
      booking: nil
    }
  end

  @doc false
  def present_booking(booking) do
    %{
      id: booking.id,
      scheduled_class_id: booking.scheduled_class_id,
      name: booking.name,
      starts_at: booking.starts_at,
      duration_minutes: Map.get(booking, :duration_minutes),
      location_id: booking.location_id,
      kind: booking |> Map.get(:kind) |> then(&(&1 && to_string(&1)))
    }
  end

  @doc false
  def present_class(class) do
    %{
      id: class.id,
      name: class.name,
      starts_at: class.starts_at,
      duration_minutes: Map.get(class, :duration_minutes),
      location_id: class.location_id,
      spots_remaining: Map.get(class, :spots_remaining)
    }
  end

  defp slot_fact(slot) do
    %{
      id: slot.id,
      name: CheckInFacts.class_name(slot),
      starts_at: slot.scheduled_at,
      duration_minutes: slot.duration_minutes,
      location_id: Map.get(slot, :location_id),
      spots_remaining: Map.get(slot, :spots_remaining)
    }
  end

  @doc false
  def present_box(door),
    do: Map.take(door, [:organization_id, :slug, :name, :logo_url, :primary_color])

  defp present_location(door), do: %{id: door.location_id, name: door.location_name}

  defp finance_reason?(reason), do: String.starts_with?(Atom.to_string(reason), "finance_")

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
