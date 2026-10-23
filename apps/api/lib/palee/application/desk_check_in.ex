defmodule Palee.Application.DeskCheckIn do
  @moduledoc """
  The check-in desk (ADR-155, decision 4) and the member's personal QR.

    * `member_code/2` - Box › Check-in: the member's personal code for this
      box, rotating (30 s, ±1 window) or static per the owner's
      `member_code_mode` (`MemberCodes`); `revoke_member_code/3` - staff end
      a static code.
    * `scan_member/4` - the desk scans a personal QR or a Wallet card: who it
      is (photo, name), their bookings in the window, the package and its
      problems, whether «auto» may check in on its own. With `auto: true`
      and nothing wrong, it checks in right away.
    * `check_in_member/5` - the desk confirms: check in to the booking (or
      the one picked), else open gym; with `override: true` despite a problem
      («Check-in παρ' όλα αυτά»), only when the owner allows it.
    * `visitors/2` - today's visitors («Επισκέπτης»), newest first.

  Every check-in records its method: `member_qr`, `wallet` or `desk_search`.
  """

  alias Palee.Application.{CheckInActions, CheckInFacts, MemberCodes, ScanCheckIn}
  alias Palee.{Facility, Identity, Organizations}
  alias Palee.Facility.Domain.{CheckInPolicy, DeskAssessment, ResolveScan}

  @methods ~w(member_qr wallet desk_search)

  @doc "The member's personal QR at this box, in the box's code mode."
  def member_code(context, now \\ DateTime.utc_now()), do: MemberCodes.current(context, now)

  @doc "Staff revoke a member's static code; its Wallet cards stop scanning."
  def revoke_member_code(context, user_id, now \\ DateTime.utc_now()) do
    with {:ok, user_id} <- uuid(user_id),
         {:ok, counts} <- MemberCodes.revoke(context, user_id, "staff", now) do
      {:ok, Map.put(counts, :user_id, user_id)}
    end
  end

  @doc "`params`: `code`, optional `location_id`, `auto`."
  def scan_member(context, staff, params, now \\ DateTime.utc_now()) do
    with {:ok, user_id, method} <- identify(context, param(params, :code), now),
         :ok <- member_of_box(context, user_id),
         {:ok, location_id} <- location(context, param(params, :location_id)) do
      view = assess(context, user_id, location_id, now)

      if param(params, :auto) == true and view.assessment.can_auto_check_in do
        with {:ok, check_in} <-
               perform(context, staff, user_id, location_id, method, view, false, now) do
          {:ok, present(context, view, method, check_in)}
        end
      else
        {:ok, present(context, view, method, nil)}
      end
    end
  end

  @doc """
  `params`: `method` (`member_qr`, `wallet`, `desk_search`; default
  `desk_search`), optional `booking_id`, `location_id`, `override`.
  """
  def check_in_member(context, staff, user_id, params, now \\ DateTime.utc_now()) do
    method = param(params, :method) || "desk_search"
    override? = param(params, :override) == true

    with true <- method in @methods || {:error, :invalid_check_in_method},
         {:ok, user_id} <- uuid(user_id),
         :ok <- member_of_box(context, user_id),
         {:ok, location_id} <- location(context, param(params, :location_id)) do
      view = assess(context, user_id, location_id, now, param(params, :booking_id))
      assessment = view.assessment

      cond do
        match?({:error, _}, assessment.decision) ->
          assessment.decision

        match?({:already_checked_in, _}, assessment.decision) ->
          {:ok, present(context, view, method, nil)}

        assessment.problems == [] and checkable?(assessment.decision) ->
          finish(context, staff, user_id, location_id, method, view, false, now)

        override? and assessment.override_allowed ->
          finish(context, staff, user_id, location_id, method, view, true, now)

        override? ->
          {:error, :override_not_allowed}

        assessment.problems != [] ->
          {:error, :check_in_problems, %{problems: Enum.map(assessment.problems, &to_string/1)}}

        true ->
          {:error, :choose_booking}
      end
    end
  end

  def visitors(context, params, now \\ DateTime.utc_now()) do
    zone = Organizations.organization_timezone(context.organization_id)
    date = param(params, :date) || CheckInPolicy.local_date(now, zone)
    {from, to} = day_bounds(date, zone)

    context
    |> Facility.list_visitor_scans(%{
      from: from,
      to: to,
      location_id: param(params, :location_id)
    })
    # ADR-186: only the doors of the desk's own branches.
    |> then(&Organizations.filter_by_location_scope(context, &1))
  end

  # -- who

  defp identify(context, code, now), do: MemberCodes.resolve(context, code, now)

  defp member_of_box(context, user_id) do
    if Organizations.membership_standing(context.organization_id, user_id) == :member,
      do: :ok,
      else: {:error, :not_a_member}
  end

  # ADR-186: a branch-scoped desk works at its own branches (its only one
  # when none is named).
  defp location(context, location_id) do
    case Organizations.desk_location(context, location_id) do
      {:ok, nil} -> {:ok, nil}
      {:ok, id} -> active_location(context, id)
      error -> error
    end
  end

  defp active_location(context, location_id) do
    case Facility.get_location(context, location_id) do
      %{archived_at: nil, id: id} -> {:ok, id}
      %{} -> {:error, :location_archived}
      nil -> {:error, :location_not_found}
    end
  end

  # -- what

  defp assess(context, user_id, location_id, now, booking_id \\ nil) do
    rules = Facility.check_in_rules(context)

    facts =
      CheckInFacts.gather(context, user_id, location_id, now, member?: true, entitlement: true)

    assessment = DeskAssessment.assess(facts, rules, now)

    assessment =
      if booking_id do
        decision =
          ResolveScan.decide(facts, rules, now, booking_id)

        %{assessment | decision: decision, can_auto_check_in: false}
      else
        assessment
      end

    %{user_id: user_id, facts: facts, rules: rules, assessment: assessment, now: now}
  end

  defp finish(context, staff, user_id, location_id, method, view, override?, now) do
    with {:ok, check_in} <-
           perform(context, staff, user_id, location_id, method, view, override?, now) do
      {:ok, present(context, view, method, check_in)}
    end
  end

  defp perform(context, staff, user_id, location_id, method, view, override?, now) do
    target =
      if override?,
        do: DeskAssessment.override_target(view.assessment.decision),
        else: target(view.assessment.decision)

    case target do
      {:class, booking} ->
        with {:ok, attendance} <-
               CheckInActions.check_in_class(context, booking, staff.id, user_id, method, now) do
          {:ok,
           %{
             kind: "class",
             id: attendance.id,
             at: attendance.marked_at,
             method: method,
             override: override?,
             booking: ScanCheckIn.present_booking(booking)
           }}
        end

      :open_gym ->
        with {:ok, check_in} <-
               CheckInActions.check_in_open_gym(
                 context,
                 staff,
                 user_id,
                 location_id,
                 method,
                 now,
                 override: override?
               ) do
          {:ok,
           %{
             kind: "open_gym",
             id: check_in.id,
             at: check_in.checked_in_at,
             method: Map.get(check_in, :method),
             override: override?,
             booking: nil
           }}
        end

      nil ->
        {:error, :choose_booking}
    end
  end

  defp target({:check_in_class, booking}), do: {:class, booking}
  defp target(:open_gym), do: :open_gym
  defp target(_decision), do: nil

  defp checkable?({:check_in_class, _booking}), do: true
  defp checkable?(:open_gym), do: true
  defp checkable?(_decision), do: false

  # -- presenting

  defp present(context, view, method, check_in) do
    person = Identity.find_by_id(view.user_id)
    assessment = view.assessment
    now_bookings = in_window(view)

    %{
      member: %{
        id: view.user_id,
        display_name: CheckInActions.display_name(person),
        nickname: person && person.nickname,
        avatar_url: person && Map.get(person, :avatar_url)
      },
      method: method,
      bookings: Enum.map(now_bookings, &ScanCheckIn.present_booking/1),
      decision: decision_name(assessment.decision),
      already_checked_in: already(assessment.decision),
      package: CheckInActions.present_package(view.facts[:entitlement]),
      problems: Enum.map(assessment.problems, &to_string/1),
      warnings: Enum.map(assessment.warnings, &to_string/1),
      can_auto_check_in: assessment.can_auto_check_in,
      override_allowed: assessment.override_allowed,
      checked_in: check_in,
      organization_id: context.organization_id
    }
  end

  defp in_window(view), do: ResolveScan.candidates(view.facts, view.rules, view.now)

  defp decision_name({:check_in_class, _booking}), do: "class"
  defp decision_name({:choose, _bookings}), do: "choose"
  defp decision_name({:already_checked_in, _what}), do: "already_checked_in"
  defp decision_name(:open_gym), do: "open_gym"
  defp decision_name({:nothing, _details}), do: "nothing"
  defp decision_name({:error, _reason}), do: "booking_not_in_window"
  defp decision_name(_decision), do: "nothing"

  defp already({:already_checked_in, {kind, _what}}), do: to_string(kind)
  defp already(_decision), do: nil

  defp day_bounds(%Date{} = date, zone) do
    {start_of(date, zone), start_of(Date.add(date, 1), zone)}
  end

  defp day_bounds(date, zone) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> day_bounds(date, zone)
      _invalid -> day_bounds(Palee.TimeZones.ZonedTime.local_date(DateTime.utc_now(), zone), zone)
    end
  end

  defp start_of(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, later} -> later
      {:error, _reason} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
