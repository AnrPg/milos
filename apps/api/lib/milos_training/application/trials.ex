defmodule MilosTraining.Application.Trials do
  @moduledoc """
  ADR-144 (P2-M3, board 6): a person who is not a member tries a class at a
  box that published its page, inside the limits the owner set.

  * **Visitor**: `offer/3` (what the box page shows), `request/3`,
    `cancel/2`, `mine/2`, `get_mine/2`, `follow_up/3`.
  * **Staff**: `policy/1`, `update_policy/2`, `queue/2`, `accept/3`,
    `decline/4`, `record_attendance/4`.

  Every ask runs under the box's trial lock, so the seats per class, the
  weekly limit and the per-person limit are exact under concurrency. A seat
  is a Scheduling booking of kind `trial` that draws on no package; it exists
  only once the trial is booked (at once, or when staff accept the ask).
  Reactions to the rest of the system (attendance, cancellations, joining
  the box) live in `TrialReactions`; timed steps in `TrialSteps`.
  """

  require Logger

  alias MilosTraining.Application.{
    AdminRecordAttendance,
    BoxConversation,
    PublicBox,
    SubmitBooking,
    TrackAnalyticsEvent,
    WithdrawBooking
  }

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

  @stages ~w(requests upcoming visited joined)
  @history_days 30
  @joined_days 90
  @follow_up_days 14
  @reminder_hours 2

  def stages, do: @stages

  # ---------------------------------------------------------------- visitor

  @doc """
  What the box page offers a signed-in visitor: whether trials are open, the
  owner's «Τι να φέρεις», the visitor's open trial here, why they can't ask
  (if so), and the trial seats left in each of `slots`. `nil` for members
  and when the owner hasn't turned trials on.
  """
  def offer(organization_id, viewer_id, slots, now \\ DateTime.utc_now())

  def offer(_organization_id, nil, _slots, _now), do: nil

  def offer(organization_id, viewer_id, slots, now) do
    context = %{organization_id: organization_id, user_id: viewer_id}
    policy = Trials.policy(context)
    standing = Organizations.membership_standing(organization_id, viewer_id)

    if policy.enabled and standing != :member do
      requests = Trials.list_requests(context, %{user_id: viewer_id, limit: 20})
      person = person_facts(policy, requests, standing)
      open = Enum.find(requests, &Trials.open?(&1.status))
      taken = Trials.open_per_class(context, Enum.map(slots, & &1.id))

      %{
        enabled: true,
        approval: policy.approval,
        bring_note: policy.bring_note,
        horizon_days: policy.horizon_days,
        blocked_reason: blocked_reason(policy, person),
        mine: open && present_brief(open),
        seats:
          Map.new(slots, fn slot ->
            {slot.id, slot_seats(policy, slot, Map.get(taken, slot.id, 0), now)}
          end)
      }
    end
  end

  @doc """
  Asks for (or books) a trial in a class of a published box. Idempotent by
  `client_operation_id`: a retry returns the trial the first call made.
  """
  def request(%{id: user_id} = user, slug, params) do
    now = DateTime.utc_now()
    operation_id = params[:client_operation_id]

    with {:ok, box, _scope} <- PublicBox.resolve(slug),
         context = %{organization_id: box.organization_id, user_id: user_id} do
      case operation_id && Trials.get_request_by_operation(context, user_id, operation_id) do
        %TrialRequest{} = existing ->
          {:ok, present_mine(context, existing, box)}

        _new ->
          with {:ok, request, booking, slot} <- ask(context, user, params, now) do
            after_ask(context, request, booking, slot, box, user)
            {:ok, present_mine(context, request, box)}
          end
      end
    end
  end

  @doc "Cancels the person's own trial: frees the seat, or withdraws the ask."
  def cancel(%{id: user_id}, trial_id) do
    with %TrialRequest{} = request <- own_request(user_id, trial_id),
         context = %{organization_id: request.organization_id, user_id: user_id},
         true <- Trials.open?(request.status) || {:error, :invalid_trial_transition},
         :ok <- release_seat(context, request, user_id),
         {:ok, cancelled} <- cancel_request(context, request) do
      {:ok, present_mine(context, cancelled)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  The person's trials at every box: upcoming ones, and recent ones that still
  have something to show (the follow-up card, a decline).
  """
  def mine(%{id: user_id}, now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -@follow_up_days, :day)

    %{user_id: user_id}
    |> Trials.list_person_requests(user_id, %{since: since})
    |> Enum.group_by(& &1.organization_id)
    |> Enum.flat_map(fn {organization_id, requests} ->
      present_many(%{organization_id: organization_id, user_id: user_id}, requests, now)
    end)
    |> Enum.sort_by(& &1.class.scheduled_at, {:asc, DateTime})
  end

  def get_mine(%{id: user_id}, trial_id) do
    case own_request(user_id, trial_id) do
      %TrialRequest{} = request ->
        {:ok,
         present_mine(%{organization_id: request.organization_id, user_id: user_id}, request)}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Board 6 Q6, after the trial: `:join` («Θέλω να γραφτώ») opens the chat with
  the box with a filled-in message; `:dismiss` («Όχι τώρα») hides the card.
  """
  def follow_up(%{id: user_id} = user, trial_id, action) when action in [:join, :dismiss] do
    now = DateTime.utc_now()

    with %TrialRequest{} = request <- own_request(user_id, trial_id),
         context = %{organization_id: request.organization_id, user_id: user_id},
         field = if(action == :join, do: :join_interest_at, else: :follow_up_dismissed_at),
         {:ok, updated} <- Trials.follow_up(context, request, field, now),
         {:ok, conversation} <- maybe_open_conversation(action, user, context) do
      if action == :join do
        TrackAnalyticsEvent.call("trial_status_changed", context, updated, %{
          metadata: %{status: "join_interest"}
        })
      end

      {:ok, %{trial: present_mine(context, updated), conversation: conversation}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp maybe_open_conversation(:dismiss, _user, _context), do: {:ok, nil}

  defp maybe_open_conversation(:join, user, context) do
    case box(context.organization_id) do
      %{slug: slug} -> BoxConversation.open(user, slug)
      nil -> {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------- staff

  @doc "The box's policy with this week's trial count, for the settings page."
  def policy(%{organization_id: organization_id} = context) do
    policy = Trials.policy(context)
    zone = Organizations.organization_timezone(organization_id)
    {from, to} = Trials.week_of(DateTime.utc_now(), zone)

    %{
      policy: present_policy(policy),
      this_week: Trials.count_in_window(context, %{from: from, to: to}, Trials.weekly_statuses())
    }
  end

  def update_policy(context, attrs) do
    with :ok <-
           valid_package(context, attrs[:conversion_package_id] || attrs["conversion_package_id"]),
         {:ok, _policy} <- Trials.update_policy(context, attrs) do
      {:ok, policy(context)}
    end
  end

  defp valid_package(_context, nil), do: :ok

  defp valid_package(context, id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         %{active: true} <- Finance.get_package(context, id) do
      :ok
    else
      _missing -> {:error, :package_not_found}
    end
  end

  @doc """
  The queue in one stage (board 6 Q4): `requests` waiting for an answer,
  `upcoming` booked trials, `visited` trials whose class has started (to
  mark Ήρθε / Δεν ήρθε) and `joined` people who became members; with the
  count in each stage and the last 30 days' funnel.
  """
  def queue(context, stage, now \\ DateTime.utc_now()) when stage in @stages do
    history = DateTime.add(now, -@history_days, :day)

    all =
      Trials.list_requests(context, %{
        statuses: ~w(requested booked attended no_show converted),
        from: DateTime.add(now, -@joined_days, :day),
        limit: 500
      })

    staged = Enum.group_by(all, &stage_of(&1, now, history))

    %{
      stage: stage,
      counts: Map.new(@stages, &{&1, length(Map.get(staged, &1, []))}),
      trials: present_queue(context, Map.get(staged, stage, []), stage),
      stats: funnel(Trials.stats(context, history))
    }
  end

  @doc "Staff accept an ask: the seat is booked now, if the class still has one."
  def accept(%{organization_id: _} = context, trial_id, %{id: actor_id}) do
    now = DateTime.utc_now()

    result =
      Trials.with_box_lock(context, fn ->
        with %TrialRequest{status: "requested"} = request <-
               Trials.get_request(context, trial_id) || {:error, :not_found},
             %{} = slot <- Scheduling.get_slot(context, request.scheduled_class_id) || gone(),
             policy = %{Trials.policy(context) | enabled: true},
             :ok <- Trials.class_check(policy, accept_facts(context, policy, slot, request, now)),
             {:ok, booking} <- book_seat(context, request.user_id, slot, nil),
             {:ok, accepted} <-
               Trials.transition(context, request, :accept, now, [by: actor_id], %{
                 booking_id: booking.id
               }) do
          {:ok, accepted, booking, slot}
        else
          %TrialRequest{} -> {:error, :invalid_trial_transition}
          error -> error
        end
      end)

    with {:ok, accepted, booking, slot} <- result do
      announce_seat(booking)
      notify_person(:trial_accepted, context, accepted, slot)
      track_status(context, accepted)
      {:ok, present_staff(context, accepted, slot)}
    end
  end

  def decline(%{organization_id: _} = context, trial_id, %{id: actor_id}, reason) do
    now = DateTime.utc_now()
    reason = reason |> to_string() |> String.trim() |> blank_to_nil()

    with %TrialRequest{} = request <-
           Trials.get_request(context, trial_id) || {:error, :not_found},
         {:ok, declined} <-
           Trials.transition(context, request, :decline, now, by: actor_id, reason: reason) do
      slot = Scheduling.get_slot(context, declined.scheduled_class_id)
      notify_person(:trial_declined, context, declined, slot)
      track_status(context, declined)
      {:ok, present_staff(context, declined, slot)}
    end
  end

  @doc """
  Ήρθε / Δεν ήρθε from the queue. It goes through the class roster, so the
  roster and the trial never disagree; `TrialReactions` moves the trial.
  """
  def record_attendance(%{organization_id: _} = context, trial_id, %{id: actor_id}, status)
      when status in ~w(attended no_show) do
    with %TrialRequest{} = request <-
           Trials.get_request(context, trial_id) || {:error, :not_found},
         true <-
           request.status in ~w(booked attended no_show) || {:error, :invalid_trial_transition},
         {:ok, _attendance} <-
           AdminRecordAttendance.call(
             context,
             request.scheduled_class_id,
             request.user_id,
             actor_id,
             %{"status" => status}
           ) do
      updated = Trials.get_request(context, trial_id)

      {:ok,
       present_staff(context, updated, Scheduling.get_slot(context, updated.scheduled_class_id))}
    end
  end

  def record_attendance(_context, _trial_id, _actor, _status), do: {:error, :bad_request}

  # ---------------------------------------------------------------- shared with reactions

  @doc false
  def cancel_request(context, request) do
    with {:ok, cancelled} <- Trials.transition(context, request, :cancel, DateTime.utc_now()) do
      notify_staff(:trial_cancelled, context, cancelled)
      track_status(context, cancelled)
      {:ok, cancelled}
    end
  end

  @doc false
  def notify_person(type, %{organization_id: organization_id}, request, slot) do
    box = box(organization_id)

    Notifications.dispatch_event(type, %{
      user_id: request.user_id,
      organization_id: organization_id,
      trial_id: request.id,
      box_name: box && box.name,
      class_name: (slot && slot.name) || request.class_name,
      class_starts_at: request.class_starts_at,
      class_when: class_when(request.class_starts_at, organization_id),
      decline_reason: request.decline_reason
    })
  end

  @doc false
  def track_status(context, request),
    do:
      TrackAnalyticsEvent.call("trial_status_changed", context, request, %{
        metadata: %{status: request.status}
      })

  # ---------------------------------------------------------------- internals

  defp ask(context, user, params, now) do
    Trials.with_box_lock(context, fn ->
      policy = Trials.policy(context)

      with {:ok, slot_id} <- required(params[:scheduled_class_id]),
           %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
           :ok <- Trials.check(policy, ask_facts(context, policy, slot, user.id, now)),
           status = Trials.initial_status(policy),
           {:ok, booking} <- maybe_book(status, context, user.id, slot, params),
           {:ok, request} <-
             Trials.insert_request(context, %{
               organization_id: context.organization_id,
               user_id: user.id,
               scheduled_class_id: slot.id,
               booking_id: booking && booking.id,
               status: status,
               note: blank_to_nil(params[:note]),
               phone: blank_to_nil(params[:phone]),
               source: params[:source] || "box_page",
               client_operation_id: params[:client_operation_id],
               class_starts_at: slot.scheduled_at,
               class_name: slot.name,
               decided_at: if(status == "booked", do: now)
             }) do
        {:ok, request, booking, slot}
      end
    end)
  end

  defp maybe_book("booked", context, user_id, slot, params),
    do: book_seat(context, user_id, slot, params[:client_operation_id])

  defp maybe_book(_status, _context, _user_id, _slot, _params), do: {:ok, nil}

  # A trial seat is always confirmed: the owner's approval setting is the
  # gate, not the class's own approval mode.
  defp book_seat(context, user_id, slot, operation_id) do
    Scheduling.submit_auto_approved_booking_with(context, user_id, slot.id, %{
      kind: "trial",
      entitlement_allowance: "none",
      client_operation_id: operation_id
    })
  end

  defp after_ask(context, request, booking, slot, _box, user) do
    if booking, do: announce_seat(booking)
    schedule_steps(context, request)

    type = if request.status == "booked", do: :trial_booked, else: :trial_requested
    notify_staff(type, context, request, slot, user)

    TrackAnalyticsEvent.call("trial_requested", context, request, %{})
  end

  defp announce_seat(booking) do
    SubmitBooking.broadcast_booking_event(%{auto_approve: true}, booking)
    :ok
  rescue
    error -> Logger.warning("trial_seat_broadcast_failed #{Exception.message(error)}")
  end

  @doc false
  def schedule_steps(%{organization_id: organization_id}, request) do
    zone = Organizations.organization_timezone(organization_id)

    trial_scheduler().schedule(organization_id, request.id,
      reminder: DateTime.add(request.class_starts_at, -@reminder_hours, :hour),
      expire: request.class_starts_at,
      follow_up: next_morning(request.class_starts_at, zone)
    )
  end

  defp notify_staff(type, context, request, slot \\ nil, person \\ nil) do
    slot = slot || Scheduling.get_slot(context, request.scheduled_class_id)
    person = person || Identity.find_by_id(request.user_id)
    box = box(context.organization_id)

    Notifications.dispatch_event(type, %{
      organization_id: context.organization_id,
      trial_id: request.id,
      person_nickname: person && person.nickname,
      box_name: box && box.name,
      class_name: (slot && slot.name) || request.class_name,
      class_starts_at: request.class_starts_at,
      class_when: class_when(request.class_starts_at, context.organization_id),
      url: "/admin/trials?stage=" <> stage_for_status(request.status)
    })
  end

  defp release_seat(_context, %{status: "requested"}, _user_id), do: :ok
  defp release_seat(_context, %{booking_id: nil}, _user_id), do: :ok

  defp release_seat(context, %{booking_id: booking_id}, user_id) do
    case WithdrawBooking.call(context, user_id, booking_id) do
      {:ok, _booking} -> :ok
      # The seat is already gone (staff removed it, or the class was deleted).
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  defp own_request(user_id, trial_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(trial_id),
         %TrialRequest{user_id: ^user_id} = request <-
           Trials.get_request(%{user_id: user_id}, trial_id) do
      request
    else
      _missing -> nil
    end
  end

  # -- facts for the rules

  defp ask_facts(context, policy, slot, user_id, now) do
    requests = Trials.list_requests(context, %{user_id: user_id, limit: 50})
    standing = Organizations.membership_standing(context.organization_id, user_id)

    slot_facts(context, slot, now)
    |> Map.put(:person, person_facts(policy, requests, standing))
  end

  # The ask being accepted already holds one trial seat and one weekly place.
  defp accept_facts(context, _policy, slot, _request, now) do
    facts = slot_facts(context, slot, now)

    %{
      facts
      | trial_seats_taken: max(facts.trial_seats_taken - 1, 0),
        week_trials: max(facts.week_trials - 1, 0)
    }
  end

  defp slot_facts(context, slot, now) do
    zone = Organizations.organization_timezone(context.organization_id)
    {from, to} = Trials.week_of(slot.scheduled_at, zone)

    %{
      slot: slot_fact(slot),
      trial_seats_taken: context |> Trials.open_per_class([slot.id]) |> Map.get(slot.id, 0),
      week_trials:
        Trials.count_in_window(context, %{from: from, to: to}, Trials.weekly_statuses()),
      now: now
    }
  end

  defp slot_fact(slot) do
    %{
      scheduled_at: slot.scheduled_at,
      class_type_id: slot.class_type_id,
      capacity: slot.capacity,
      booked: Map.get(slot, :approved_booking_count, 0)
    }
  end

  defp person_facts(policy, requests, standing) do
    %{
      member?: standing == :member,
      ever_member?: standing != :none,
      consumed: Enum.count(requests, &Trials.consumes?(&1.status, policy.no_show_consumes)),
      open?: Enum.any?(requests, &Trials.open?(&1.status))
    }
  end

  defp blocked_reason(policy, person) do
    case Trials.person_check(policy, person) do
      :ok -> nil
      {:error, :trial_already_open} -> nil
      {:error, reason} -> reason
    end
  end

  defp slot_seats(policy, slot, taken, now) do
    facts = %{slot: slot_fact(slot), trial_seats_taken: taken, week_trials: 0, now: now}

    case Trials.class_check(policy, facts) do
      :ok -> Trials.seats_left(policy, facts.slot, taken)
      {:error, _reason} -> 0
    end
    |> then(fn seats -> if Trials.open_type?(policy, slot), do: seats end)
  end

  # -- queue stages

  defp stage_of(%{status: "requested"}, _now, _history), do: "requests"

  defp stage_of(%{status: "booked"} = request, now, history) do
    cond do
      DateTime.compare(request.class_starts_at, now) == :gt -> "upcoming"
      DateTime.compare(request.class_starts_at, history) == :lt -> nil
      true -> "visited"
    end
  end

  defp stage_of(%{status: status} = request, _now, history) when status in ~w(attended no_show),
    do: if(DateTime.compare(request.class_starts_at, history) == :lt, do: nil, else: "visited")

  defp stage_of(%{status: "converted"}, _now, _history), do: "joined"
  defp stage_of(_request, _now, _history), do: nil

  defp stage_for_status("requested"), do: "requests"
  defp stage_for_status("booked"), do: "upcoming"
  defp stage_for_status(_status), do: "visited"

  defp funnel(stats) do
    count = &Map.get(stats, &1, 0)
    came = count.("attended") + count.("converted")

    %{
      days: @history_days,
      requested: Enum.sum(Map.values(stats)),
      booked: count.("booked") + count.("attended") + count.("no_show") + count.("converted"),
      attended: came,
      no_show: count.("no_show"),
      converted: count.("converted"),
      declined: count.("declined"),
      cancelled: count.("cancelled") + count.("expired")
    }
  end

  # -- presenters

  defp present_policy(policy) do
    Map.take(policy, [
      :enabled,
      :approval,
      :weekly_limit,
      :per_person_limit,
      :seats_per_class,
      :class_type_ids,
      :horizon_days,
      :first_timers_only,
      :no_show_consumes,
      :bring_note,
      :conversion_package_id
    ])
  end

  defp present_queue(_context, [], _stage), do: []

  defp present_queue(context, requests, stage) do
    slots = slots_by_id(context, requests)
    people = requests |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    requests
    |> Enum.map(&present_staff_row(&1, slots[&1.scheduled_class_id], people[&1.user_id]))
    |> sort_stage(stage)
  end

  defp sort_stage(rows, stage) when stage in ~w(requests upcoming),
    do: Enum.sort_by(rows, & &1.class_starts_at, {:asc, DateTime})

  defp sort_stage(rows, _stage), do: Enum.sort_by(rows, & &1.class_starts_at, {:desc, DateTime})

  defp present_staff(context, request, slot) do
    person = Identity.find_by_id(request.user_id)

    present_staff_row(
      request,
      slot || Scheduling.get_slot(context, request.scheduled_class_id),
      person
    )
  end

  defp present_staff_row(request, slot, person) do
    request
    |> base()
    |> Map.merge(%{
      person: person && present_person(person),
      phone: request.phone,
      source: request.source,
      decided_by_id: request.decided_by_id,
      join_interest_at: request.join_interest_at,
      class: present_class(slot, request)
    })
  end

  defp present_person(person),
    do: %{id: person.id, nickname: person.nickname, avatar_url: Map.get(person, :avatar_url)}

  defp present_many(context, requests, now) do
    slots = slots_by_id(context, requests)
    box = box(context.organization_id)
    policy = Trials.policy(context)
    locations = locations_by_id(context)

    requests
    |> Enum.filter(&visible_to_person?(&1, now))
    |> Enum.map(&present_mine_row(&1, slots[&1.scheduled_class_id], box, policy, locations, now))
  end

  defp present_mine(context, request, box \\ nil) do
    slot = Scheduling.get_slot(context, request.scheduled_class_id)
    box = box || box(context.organization_id)
    policy = Trials.policy(context)
    present_mine_row(request, slot, box, policy, locations_by_id(context), DateTime.utc_now())
  end

  defp present_mine_row(request, slot, box, policy, locations, now) do
    location = slot && locations[Map.get(slot, :location_id)]

    request
    |> base()
    |> Map.merge(%{
      box: box,
      class: present_class(slot, request),
      location: location,
      bring_note: policy.bring_note,
      follow_up: follow_up_due?(request, now)
    })
  end

  defp present_brief(request),
    do: %{id: request.id, status: request.status, scheduled_class_id: request.scheduled_class_id}

  defp base(request) do
    Map.take(request, [
      :id,
      :organization_id,
      :user_id,
      :scheduled_class_id,
      :booking_id,
      :status,
      :note,
      :class_starts_at,
      :decided_at,
      :decline_reason,
      :attended_at,
      :converted_at,
      :cancelled_at,
      :inserted_at
    ])
  end

  defp present_class(nil, request),
    do: %{
      id: request.scheduled_class_id,
      name: request.class_name,
      scheduled_at: request.class_starts_at,
      duration_minutes: nil,
      location_id: nil,
      class_type: nil
    }

  defp present_class(slot, _request) do
    %{
      id: slot.id,
      name: slot.name,
      scheduled_at: slot.scheduled_at,
      duration_minutes: slot.duration_minutes,
      location_id: Map.get(slot, :location_id),
      class_type: slot.class_type && Map.take(slot.class_type, [:id, :name])
    }
  end

  # Upcoming and open trials always show; past ones only while there is
  # something left to do or read.
  defp visible_to_person?(request, now) do
    Trials.open?(request.status) or follow_up_due?(request, now) or
      (request.status in ~w(declined cancelled expired no_show converted) and
         DateTime.compare(request.class_starts_at, DateTime.add(now, -2, :day)) == :gt)
  end

  defp follow_up_due?(request, now) do
    request.status == "attended" and is_nil(request.join_interest_at) and
      is_nil(request.follow_up_dismissed_at) and
      DateTime.compare(request.class_starts_at, DateTime.add(now, -@follow_up_days, :day)) == :gt
  end

  defp slots_by_id(context, requests) do
    context
    |> Scheduling.list_slots_by_ids(
      requests
      |> Enum.map(& &1.scheduled_class_id)
      |> Enum.reject(&is_nil/1)
    )
    |> Map.new(&{&1.id, &1})
  end

  defp locations_by_id(context) do
    context
    |> Facility.list_locations()
    |> Map.new(fn location ->
      {location.id,
       Map.take(location, [:id, :name, :address, :city, :neighbourhood, :latitude, :longitude])}
    end)
  end

  defp box(organization_id),
    do: organization_id |> List.wrap() |> Organizations.public_boxes() |> List.first()

  # -- time

  @doc false
  def class_when(nil, _organization_id), do: nil

  def class_when(at, organization_id) do
    zone = Organizations.organization_timezone(organization_id)

    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> Calendar.strftime(local, "%d/%m %H:%M")
      {:error, _reason} -> Calendar.strftime(at, "%d/%m %H:%M UTC")
    end
  end

  # The follow-up goes out at 10:00 (box time) the day after the class.
  defp next_morning(at, zone) do
    local =
      case DateTime.shift_zone(at, zone) do
        {:ok, local} -> local
        {:error, _reason} -> at
      end

    date = local |> DateTime.to_date() |> Date.add(1)

    case DateTime.new(date, ~T[10:00:00], zone) do
      {:ok, morning} -> DateTime.shift_zone!(morning, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:error, _reason} -> DateTime.add(at, 18, :hour)
    end
  end

  # -- small helpers

  defp required(value) when is_binary(value) and value != "", do: {:ok, value}
  defp required(_value), do: {:error, :bad_request}

  defp gone, do: {:error, :class_not_found}

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp blank_to_nil(value), do: value

  defp trial_scheduler, do: Application.fetch_env!(:milos_training, :trial_scheduler)
end
