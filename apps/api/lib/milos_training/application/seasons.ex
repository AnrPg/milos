defmodule MilosTraining.Application.Seasons do
  @moduledoc """
  Seasons (ADR-167, P3-M5): the gym sells a fixed-length programme; a member
  asks for a place in `Box › Συνδρομή`; staff confirm or decline, as they do
  with packages (no card processor, plan D5).

  Confirming a place, in one transaction under the season's lock:

    1. grants the season's membership package through Finance (the same
       subscription staff assign by hand, priced at the season's price), so
       payments and entitlements follow the existing finance flow;
    2. adds the member to the season's invite-only `#season` channel in the
       gym's club (created, with a pinned welcome, on the first confirmation);
    3. schedules the programme as ordinary assigned workouts labelled with the
       season, from the start date (or today, when confirmed mid-season).

  Leaving a season (staff remove a participant, or the gym cancels the
  season) takes the member out of the channel and drops their programme from
  today on; the Finance subscription stays for staff to settle in Finance.
  """

  require Logger

  alias MilosTraining.Application.{
    AssignFinanceMemberPackage,
    BoxPublicProfile,
    BroadcastUserSync,
    RealtimePublisher
  }

  alias MilosTraining.{Community, Finance, Identity, Notifications, Organizations, Seasons}
  alias MilosTraining.Workouts

  @admin_statuses ~w(draft published cancelled)

  # ------------------------------------------------------------------ staff

  @doc """
  The gym's seasons, newest start first, with their place counts, and the
  staff the builder may name as a season's coaches.
  """
  def list(context) do
    offerings = Seasons.list_offerings(context)
    counts = Seasons.enrollment_counts(context, Enum.map(offerings, & &1.id))
    today = today(context)
    coaches = coach_directory(offerings)

    %{
      seasons: Enum.map(offerings, &present(&1, counts, today, coaches, :staff)),
      coach_candidates: BoxPublicProfile.coach_candidates(context.organization_id)
    }
  end

  @doc "One season with every enrollment, for the builder's detail sheet."
  def show(context, id) do
    with {:ok, offering} <- fetch(context, id) do
      {:ok, staff_detail(context, offering)}
    end
  end

  def create(context, attrs) do
    status = requested_status(attrs, "draft")
    attrs = editable(attrs)

    with :ok <- valid_status(status, nil),
         {:ok, attrs} <- check_references(context, attrs) do
      context
      |> Seasons.create_offering(
        Map.merge(attrs, %{
          status: status,
          created_by_id: context.user_id,
          published_at: if(status == "published", do: DateTime.utc_now())
        })
      )
      |> case do
        {:ok, offering} -> {:ok, staff_detail(context, offering)}
        error -> error
      end
    end
  end

  def update(context, id, attrs) do
    with {:ok, offering} <- fetch(context, id) do
      Seasons.with_offering_lock(context, offering.id, fn ->
        offering = Seasons.get_offering(context, offering.id)
        do_update(context, offering, attrs)
      end)
      |> after_update(context)
    end
  end

  defp do_update(context, offering, attrs) do
    changes = editable(attrs)
    status = requested_status(attrs, offering.status)
    counts = counts_for(context, offering)

    with :ok <- valid_status(status, offering.status),
         :ok <- not_ended(offering, today(context)),
         :ok <- schedule_unlocked(offering, changes, counts),
         :ok <- capacity_fits(changes, counts),
         :ok <- unpublish_allowed(offering, status, counts),
         {:ok, changes} <- check_references(context, changes) do
      cond do
        status == "cancelled" and offering.status != "cancelled" ->
          cancel_offering(context, offering, changes)

        true ->
          published_at =
            if status == "published" and is_nil(offering.published_at),
              do: DateTime.utc_now(),
              else: offering.published_at

          with {:ok, updated} <-
                 Seasons.update_offering(
                   context,
                   offering,
                   Map.merge(changes, %{status: status, published_at: published_at})
                 ),
               :ok <- rename_channel(context, updated, changes) do
            {:ok, {updated, []}}
          end
      end
    end
  end

  defp after_update({:ok, {offering, notices}}, context) do
    Enum.each(notices, &notify(context, &1))
    announce_channels(context)
    {:ok, staff_detail(context, offering)}
  end

  defp after_update(error, _context), do: error

  @doc "Confirms a request (or a waitlisted one, when a place is free)."
  def confirm(context, enrollment_id) do
    now = DateTime.utc_now()
    today = today(context)

    with {:ok, enrollment} <- fetch_enrollment(context, enrollment_id) do
      Seasons.with_offering_lock(context, enrollment.season_offering_id, fn ->
        enrollment = Seasons.get_enrollment(context, enrollment.id)
        offering = Seasons.get_offering(context, enrollment.season_offering_id)
        counts = counts_for(context, offering)

        with :ok <- Seasons.request_check(offering, today),
             :ok <- place_free(offering, counts),
             {:ok, _check} <- can_step(enrollment, :confirm, now),
             {:ok, subscription_id} <- grant_package(context, offering, enrollment.user_id),
             {:ok, offering} <- ensure_channel(context, offering),
             :ok <- join_channel(context, offering, enrollment.user_id),
             :ok <- schedule_programme(context, offering, enrollment.user_id, today),
             {:ok, confirmed} <-
               Seasons.transition(context, enrollment, :confirm, now, [by: context.user_id], %{
                 package_subscription_id: subscription_id
               }) do
          {:ok, {offering, confirmed}}
        end
      end)
      |> case do
        {:ok, {offering, confirmed}} ->
          BroadcastUserSync.for_users([confirmed.user_id], ["assigned_workouts"],
            reason: "season_confirmed",
            payload: %{season_id: offering.id}
          )

          announce_channels(context)
          notify(context, {:season_confirmed, offering, confirmed, %{}})
          {:ok, staff_detail(context, offering)}

        error ->
          error
      end
    end
  end

  @doc "Declines a request, with an optional reason the member sees."
  def decline(context, enrollment_id, reason) do
    staff_step(context, enrollment_id, fn offering, enrollment, now ->
      with {:ok, declined} <-
             Seasons.transition(context, enrollment, :decline, now,
               by: context.user_id,
               reason: blank_to_nil(reason)
             ) do
        notices = [{:season_declined, offering, declined, %{reason: declined.decline_reason}}]
        {:ok, {offering, notices ++ promote(context, offering, enrollment.status, now)}}
      end
    end)
  end

  @doc "Takes a member out of the season (any open or active place)."
  def remove(context, enrollment_id) do
    staff_step(context, enrollment_id, fn offering, enrollment, now ->
      with {:ok, _cancelled} <- Seasons.transition(context, enrollment, :cancel, now),
           :ok <- leave(context, offering, enrollment) do
        {:ok, {offering, promote(context, offering, enrollment.status, now)}}
      end
    end)
  end

  defp staff_step(context, enrollment_id, fun) do
    now = DateTime.utc_now()

    with {:ok, enrollment} <- fetch_enrollment(context, enrollment_id) do
      Seasons.with_offering_lock(context, enrollment.season_offering_id, fn ->
        enrollment = Seasons.get_enrollment(context, enrollment.id)
        offering = Seasons.get_offering(context, enrollment.season_offering_id)
        fun.(offering, enrollment, now)
      end)
      |> after_update(context)
    end
  end

  # ---------------------------------------------------------------- members

  @doc """
  The seasons a member sees in `Box › Συνδρομή`: every published or running
  season of the gym, and any other they hold or held a place in.
  """
  def member_list(context) do
    today = today(context)

    mine =
      context
      |> Seasons.list_member_enrollments(context.user_id)
      |> Map.new(&{&1.season_offering_id, &1})

    offerings =
      context
      |> Seasons.list_offerings(%{statuses: ~w(published running completed cancelled)})
      |> Enum.filter(fn offering ->
        Seasons.open?(offering, today) or member_kept?(Map.get(mine, offering.id))
      end)
      |> Enum.sort_by(&{Date.to_gregorian_days(&1.starts_on), &1.title})

    counts = Seasons.enrollment_counts(context, Enum.map(offerings, & &1.id))
    coaches = coach_directory(offerings)

    %{
      seasons:
        Enum.map(offerings, fn offering ->
          offering
          |> present(counts, today, coaches, :member)
          |> Map.put(:mine, present_mine(Map.get(mine, offering.id)))
        end)
    }
  end

  @doc "A member asks for a place; a full season puts them on its waitlist."
  def request(context, offering_id) do
    now = DateTime.utc_now()
    today = today(context)
    user_id = context.user_id

    with {:ok, offering} <- fetch(context, offering_id) do
      Seasons.with_offering_lock(context, offering.id, fn ->
        offering = Seasons.get_offering(context, offering.id)
        existing = Seasons.get_member_enrollment(context, offering.id, user_id)
        counts = counts_for(context, offering)

        with :ok <- Seasons.request_check(offering, today),
             :ok <- may_request(existing),
             status = Seasons.request_status(offering.capacity, held(counts)),
             {:ok, enrollment} <-
               Seasons.request(context, offering, user_id, existing, status, now) do
          {:ok, {offering, enrollment}}
        end
      end)
      |> case do
        {:ok, {offering, enrollment}} ->
          notify_staff(context, offering, enrollment)
          {:ok, member_view(context, offering, enrollment)}

        error ->
          error
      end
    end
  end

  @doc """
  A member withdraws an open request or their waitlist place. A confirmed
  place is settled with the box (money is involved), so it is refused here.
  """
  def cancel(context, offering_id) do
    now = DateTime.utc_now()

    with {:ok, offering} <- fetch(context, offering_id) do
      Seasons.with_offering_lock(context, offering.id, fn ->
        enrollment = Seasons.get_member_enrollment(context, offering.id, context.user_id)

        cond do
          is_nil(enrollment) ->
            {:error, :not_found}

          enrollment.status == "active" ->
            {:error, :season_place_confirmed}

          true ->
            with {:ok, cancelled} <- Seasons.transition(context, enrollment, :cancel, now) do
              {:ok, {offering, cancelled, promote(context, offering, enrollment.status, now)}}
            end
        end
      end)
      |> case do
        {:ok, {offering, cancelled, notices}} ->
          Enum.each(notices, &notify(context, &1))
          {:ok, member_view(context, offering, cancelled)}

        error ->
          error
      end
    end
  end

  # ------------------------------------------------------- assigned workouts

  @doc """
  ADR-167: labels assigned workouts that belong to a season with the
  season's title (`season: %{id, title}`), for Box and the journal.
  """
  def label_assignments(context, assignments) do
    ids =
      assignments
      |> Enum.map(&Map.get(&1, :season_offering_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    titles = if ids == [], do: %{}, else: Seasons.titles(context, ids)

    Enum.map(assignments, fn assignment ->
      case Map.get(assignment, :season_offering_id) do
        nil ->
          Map.put(assignment, :season, nil)

        id ->
          Map.put(assignment, :season, %{id: id, title: Map.get(titles, id)})
      end
    end)
  end

  # ---------------------------------------------------------------- sweeps

  @doc """
  The daily sweep for one gym: a published season whose start came becomes
  running; a season past its last day completes (its participants complete,
  open requests close) and its channel is archived.
  """
  def sweep(%{organization_id: _} = context) do
    today = today(context)
    now = DateTime.utc_now()
    live = Seasons.list_offerings(context, %{statuses: ~w(published running)})

    ended =
      Enum.flat_map(live, fn offering ->
        case Seasons.effective_status(offering, today) do
          "running" when offering.status == "published" ->
            {:ok, _} = Seasons.update_offering(context, offering, %{status: "running"})
            []

          "completed" ->
            complete(context, offering, now)
            [offering]

          _same ->
            []
        end
      end)

    if Enum.any?(ended, & &1.channel_id) do
      ended_ids = MapSet.new(ended, & &1.id)
      live_ids = for offering <- live, not MapSet.member?(ended_ids, offering.id), do: offering.id
      :ok = Community.archive_ended_season_channels(context, live_ids)
      announce_channels(context)
    end

    :ok
  end

  defp complete(context, offering, now) do
    Seasons.with_offering_lock(context, offering.id, fn ->
      context
      |> Seasons.list_enrollments(offering.id)
      |> Enum.each(fn enrollment ->
        step =
          case enrollment.status do
            "active" -> :complete
            status when status in ["requested", "waitlisted"] -> :cancel
            _closed -> nil
          end

        if step, do: {:ok, _} = Seasons.transition(context, enrollment, step, now)
      end)

      Seasons.update_offering(context, offering, %{status: "completed"})
    end)
  end

  # --------------------------------------------------------------- internals

  defp cancel_offering(context, offering, changes) do
    now = DateTime.utc_now()

    notices =
      context
      |> Seasons.list_enrollments(offering.id)
      |> Enum.filter(&(&1.status in ~w(requested waitlisted active)))
      |> Enum.map(fn enrollment ->
        {:ok, cancelled} = Seasons.transition(context, enrollment, :cancel, now)
        :ok = leave(context, offering, enrollment)
        {:season_cancelled, offering, cancelled, %{}}
      end)

    with {:ok, updated} <-
           Seasons.update_offering(
             context,
             offering,
             Map.merge(changes, %{status: "cancelled", cancelled_at: now})
           ),
         :ok <- archive_channel(context, updated) do
      {:ok, {updated, notices}}
    end
  end

  defp archive_channel(_context, %{channel_id: nil}), do: :ok

  defp archive_channel(context, _offering) do
    live_ids =
      context
      |> Seasons.list_offerings(%{statuses: ~w(published running)})
      |> Enum.map(& &1.id)

    Community.archive_ended_season_channels(context, live_ids)
  end

  # A freed place (an open request or an active participant left) goes to
  # the earliest waitlisted member, as a request staff still confirm.
  defp promote(context, offering, freed_status, now) when freed_status in ~w(requested active) do
    case Seasons.first_waitlisted(context, offering.id) do
      nil ->
        []

      waiting ->
        {:ok, promoted} = Seasons.transition(context, waiting, :promote, now)
        [{:season_requested, offering, promoted, %{}}]
    end
  end

  defp promote(_context, _offering, _freed_status, _now), do: []

  defp leave(context, offering, %{status: "active", user_id: user_id}) do
    with {:ok, _removed} <-
           Workouts.remove_season_athlete(context, offering.id, user_id, today(context)) do
      case channel(context, offering) do
        nil -> :ok
        channel -> Community.remove_season_participant(context, channel, user_id)
      end
    end
  end

  defp leave(_context, _offering, _enrollment), do: :ok

  defp grant_package(_context, %{membership_package_id: nil}, _user_id), do: {:ok, nil}

  defp grant_package(context, offering, user_id) do
    Finance.with_tenant_context(context, fn ->
      AssignFinanceMemberPackage.call(
        context,
        user_id,
        %{
          "membership_package_id" => offering.membership_package_id,
          "starts_on" => offering.starts_on,
          "ends_on" => Seasons.ends_on(offering),
          "signup_source" => "direct"
        },
        price_cents: offering.price_cents
      )
    end)
    |> case do
      {:ok, subscription} -> {:ok, subscription.id}
      {:error, reason} -> {:error, reason}
    end
  end

  # The first confirmation creates the channel and pins the gym's welcome.
  defp ensure_channel(context, offering) do
    with {:ok, channel} <- Community.ensure_season_channel(context, offering) do
      if offering.channel_id == channel.id do
        {:ok, offering}
      else
        with {:ok, offering} <-
               Seasons.update_offering(context, offering, %{channel_id: channel.id}),
             :ok <- welcome(context, offering, channel) do
          {:ok, offering}
        end
      end
    end
  end

  defp welcome(context, offering, channel) do
    body = offering.welcome_message || offering.description || offering.title
    now = DateTime.utc_now()

    with {:ok, post} <-
           Community.create_post(context, channel, "staff", true, %{
             body: body,
             audience: "club_channel"
           }),
         {:ok, _pinned} <- Community.pin_post(context, post, channel, "staff", true, now) do
      :ok
    end
  end

  defp join_channel(context, offering, user_id) do
    case channel(context, offering) do
      nil -> {:error, :not_found}
      channel -> Community.add_season_participant(context, channel, user_id)
    end
  end

  defp channel(_context, %{channel_id: nil}), do: nil
  defp channel(context, %{channel_id: id}), do: Community.get_channel(context, id)

  defp rename_channel(context, %{channel_id: id} = offering, %{title: _title})
       when is_binary(id) do
    case Community.ensure_season_channel(context, offering) do
      {:ok, _channel} -> :ok
      error -> error
    end
  end

  defp rename_channel(_context, _offering, _changes), do: :ok

  defp schedule_programme(context, offering, user_id, today) do
    from = Enum.max([offering.starts_on, today], Date)

    offering.programme
    |> then(&Seasons.schedule(&1, offering.starts_on, from))
    |> Enum.reduce_while(:ok, fn {date, workout_id}, :ok ->
      case Workouts.assign_workout(context, %{
             master_workout_id: workout_id,
             scheduled_for: date,
             athlete_ids: [user_id],
             season_offering_id: offering.id
           }) do
        {:ok, _assignment} -> {:cont, :ok}
        {:error, %Ecto.Changeset{}} -> {:halt, {:error, :programme_workout_unavailable}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_references(context, attrs) do
    with :ok <- check_package(context, Map.get(attrs, :membership_package_id)),
         :ok <- check_workouts(context, Map.get(attrs, :programme)),
         {:ok, attrs} <- check_coaches(context, attrs) do
      {:ok, attrs}
    end
  end

  defp check_package(_context, nil), do: :ok

  defp check_package(context, package_id) do
    case Finance.get_package(context, package_id) do
      %{active: true} -> :ok
      _other -> {:error, :package_not_found}
    end
  end

  defp check_workouts(_context, nil), do: :ok

  defp check_workouts(context, programme) when is_list(programme) do
    programme
    |> Enum.map(&(Map.get(&1, "workout_id") || Map.get(&1, :workout_id)))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.all?(fn id ->
      match?({:ok, _}, Ecto.UUID.cast(id)) and published?(Workouts.get_workout(context, id))
    end)
    |> if(do: :ok, else: {:error, :programme_workout_unavailable})
  end

  defp check_workouts(_context, _programme), do: :ok

  defp published?(%{status: status}), do: to_string(status) == "published"
  defp published?(_workout), do: false

  defp check_coaches(context, %{coach_ids: ids} = attrs) when is_list(ids) do
    staff = MapSet.new(Organizations.list_staff_user_ids(context.organization_id))
    ids = Enum.uniq(ids)

    if Enum.all?(ids, &MapSet.member?(staff, &1)),
      do: {:ok, Map.put(attrs, :coach_ids, ids)},
      else: {:error, :not_a_coach}
  end

  defp check_coaches(_context, attrs), do: {:ok, attrs}

  defp valid_status(status, _current) when status in @admin_statuses, do: :ok
  defp valid_status(_status, _current), do: {:error, :invalid_season_status}

  defp not_ended(%{status: status}, _today) when status in ~w(completed cancelled),
    do: {:error, :season_closed}

  defp not_ended(_offering, _today), do: :ok

  defp schedule_unlocked(offering, changes, counts) do
    touches? =
      Enum.any?(Seasons.schedule_fields(), fn field ->
        Map.has_key?(changes, field) and Map.get(changes, field) != Map.get(offering, field)
      end)

    if touches? and Seasons.schedule_locked?(Map.get(counts, "active", 0)),
      do: {:error, :season_schedule_locked},
      else: :ok
  end

  defp capacity_fits(%{capacity: capacity}, counts) when is_integer(capacity) do
    if capacity < Map.get(counts, "active", 0),
      do: {:error, :capacity_below_participants},
      else: :ok
  end

  defp capacity_fits(_changes, _counts), do: :ok

  # A season people already asked for stays published (cancel it instead).
  defp unpublish_allowed(%{status: "published"}, "draft", counts) do
    if Enum.any?(~w(requested waitlisted active), &(Map.get(counts, &1, 0) > 0)),
      do: {:error, :season_has_enrollments},
      else: :ok
  end

  defp unpublish_allowed(_offering, _status, _counts), do: :ok

  defp place_free(offering, counts) do
    if Seasons.can_confirm?(offering.capacity, Map.get(counts, "active", 0)),
      do: :ok,
      else: {:error, :season_full}
  end

  defp can_step(enrollment, step, now), do: Seasons.check_step(enrollment, step, now)

  defp may_request(existing) do
    if Seasons.can_request?(existing && existing.status),
      do: :ok,
      else: {:error, :season_already_requested}
  end

  defp held(counts), do: Map.get(counts, "requested", 0) + Map.get(counts, "active", 0)

  defp counts_for(context, offering),
    do: context |> Seasons.enrollment_counts([offering.id]) |> Map.get(offering.id, %{})

  defp member_kept?(nil), do: false
  defp member_kept?(%{status: status}), do: status in ~w(requested waitlisted active completed)

  defp fetch(context, id) do
    case Seasons.get_offering(context, id) do
      nil -> {:error, :not_found}
      offering -> {:ok, offering}
    end
  end

  defp fetch_enrollment(context, id) do
    case Seasons.get_enrollment(context, id) do
      nil -> {:error, :not_found}
      enrollment -> {:ok, enrollment}
    end
  end

  defp editable(attrs) do
    allowed = Map.new(Seasons.editable_fields(), &{to_string(&1), &1})

    attrs
    |> Enum.flat_map(fn {key, value} ->
      case Map.fetch(allowed, to_string(key)) do
        {:ok, field} -> [{field, value}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp requested_status(attrs, default) do
    case Map.get(attrs, :status) || Map.get(attrs, "status") do
      nil -> default
      status -> to_string(status)
    end
  end

  defp today(%{organization_id: organization_id}) do
    organization_id
    |> Organizations.organization_timezone()
    |> DateTime.now!()
    |> DateTime.to_date()
  end

  # ---------------------------------------------------------------- views

  defp staff_detail(context, offering) do
    today = today(context)
    counts = Seasons.enrollment_counts(context, [offering.id])
    enrollments = Seasons.list_enrollments(context, offering.id)

    people =
      enrollments |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    offering
    |> present(counts, today, coach_directory([offering]), :staff)
    |> Map.put(
      :enrollments,
      Enum.map(enrollments, fn enrollment ->
        person = Map.get(people, enrollment.user_id)

        %{
          id: enrollment.id,
          user_id: enrollment.user_id,
          nickname: person && person.nickname,
          status: enrollment.status,
          requested_at: enrollment.requested_at,
          decided_at: enrollment.decided_at,
          decline_reason: enrollment.decline_reason,
          package_subscription_id: enrollment.package_subscription_id
        }
      end)
    )
  end

  defp member_view(context, offering, enrollment) do
    counts = Seasons.enrollment_counts(context, [offering.id])

    offering
    |> present(counts, today(context), coach_directory([offering]), :member)
    |> Map.put(:mine, present_mine(enrollment))
  end

  defp present(offering, counts, today, coaches, audience) do
    counts = Map.get(counts, offering.id, %{})
    held = held(counts)

    base = %{
      id: offering.id,
      title: offering.title,
      description: offering.description,
      starts_on: offering.starts_on,
      ends_on: Seasons.ends_on(offering),
      weeks: offering.weeks,
      capacity: offering.capacity,
      places_left: max(offering.capacity - held, 0),
      price_cents: offering.price_cents,
      currency: offering.currency,
      status: Seasons.effective_status(offering, today),
      workout_count: length(offering.programme),
      coaches:
        offering.coach_ids
        |> Enum.map(&Map.get(coaches, &1))
        |> Enum.reject(&is_nil/1)
    }

    case audience do
      :member ->
        base

      :staff ->
        Map.merge(base, %{
          welcome_message: offering.welcome_message,
          membership_package_id: offering.membership_package_id,
          programme: offering.programme,
          coach_ids: offering.coach_ids,
          channel_id: offering.channel_id,
          counts: %{
            requested: Map.get(counts, "requested", 0),
            waitlisted: Map.get(counts, "waitlisted", 0),
            active: Map.get(counts, "active", 0)
          }
        })
    end
  end

  defp present_mine(nil), do: nil

  defp present_mine(enrollment) do
    %{
      id: enrollment.id,
      status: enrollment.status,
      decline_reason: enrollment.decline_reason,
      requested_at: enrollment.requested_at
    }
  end

  defp coach_directory(offerings) do
    offerings
    |> Enum.flat_map(& &1.coach_ids)
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      ids ->
        ids |> Identity.list_by_ids() |> Map.new(&{&1.id, %{id: &1.id, nickname: &1.nickname}})
    end
  end

  # ---------------------------------------------------------------- notices

  defp notify_staff(context, offering, enrollment) do
    notify(context, {:season_requested, offering, enrollment, %{}})
  end

  defp notify(context, {:season_requested = type, offering, enrollment, extra}) do
    recipients =
      (Organizations.list_user_ids_with_capability(context.organization_id, :take_payments) ++
         offering.coach_ids)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == enrollment.user_id))

    person = Identity.find_by_id(enrollment.user_id)

    Enum.each(recipients, fn user_id ->
      dispatch(context, type, user_id, offering, enrollment, Map.put(extra, :person, person))
    end)
  end

  defp notify(context, {type, offering, enrollment, extra}),
    do: dispatch(context, type, enrollment.user_id, offering, enrollment, extra)

  defp dispatch(context, type, user_id, offering, enrollment, extra) do
    box = Organizations.brand_summary(context.organization_id)
    person = Map.get(extra, :person)

    Notifications.dispatch_event(type, %{
      user_id: user_id,
      organization_id: context.organization_id,
      season_id: offering.id,
      season_title: offering.title,
      starts_on: Date.to_iso8601(offering.starts_on),
      enrollment_id: enrollment.id,
      enrollment_status: enrollment.status,
      person_nickname: person && person.nickname,
      box_name: box && box.name,
      reason: Map.get(extra, :reason),
      at: DateTime.to_unix(enrollment.updated_at || DateTime.utc_now(), :microsecond)
    })
  rescue
    error -> Logger.warning("season_notification_failed #{Exception.message(error)}")
  end

  defp announce_channels(%{organization_id: organization_id} = context) do
    context
    |> Community.list_clubs([organization_id])
    |> Enum.filter(&(&1.kind == "gym"))
    |> Enum.each(fn club ->
      RealtimePublisher.broadcast("community:club:#{club.id}", "channels_changed", %{
        club_id: club.id
      })
    end)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
