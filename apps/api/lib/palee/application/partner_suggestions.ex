defmodule Palee.Application.PartnerSuggestions do
  @moduledoc """
  «Κλείστε μαζί» for a public Partners match (ADR-280 §4).

  * `suggestions/3`: up to three activities for the two people of a match,
    from the classes of a box both belong to and, near both, the events and
    trial classes Γύρω μου shows, ranked by `Partners.Suggestions`
    (the deterministic `SuggestionPolicy`). Counts `shown`.
  * `propose/4`: posts one of them as a plan in the conversation, after
    checking it is still a suggestion. Counts `proposed`.
  * `feedback/3`: «Δεν ταιριάζει» on one suggestion. Counts `feedback`.
  * `stats/2`: the vendors' daily counters of the last 30 days.

  Candidates come only through other contexts' public APIs (Scheduling,
  Community, Trials, Places, Facility, Organizations). For each activity
  only whether these two are booked is read and returned, never who else.
  The match itself (`own_match/2`, `post_plan/3`) belongs to
  `PartnerMatches`, reached through `:partner_matches_api`.
  """

  alias Palee.Application.{AroundMe, CommunityEvents, Trials}
  alias Palee.{Community, Facility, Organizations, Places, Scheduling}
  alias Palee.Partners.Suggestions

  @matches Application.compile_env(
             :palee,
             :partner_matches_api,
             Palee.Application.PartnerMatches
           )

  @booked_statuses [:pending, :approved, "pending", "approved"]
  @event_limit 30
  @trial_box_limit 5
  @stats_days 30

  # ------------------------------------------------------------------ member

  @doc "Up to three suggestions for the match: `{:ok, %{suggestions: [...]}}`."
  def suggestions(context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, ranked} <- ranked(context, match_id, now) do
      if ranked != [], do: Suggestions.count(context, "shown")
      {:ok, %{suggestions: Enum.map(ranked, &present(&1, context.user_id))}}
    end
  end

  @doc """
  Posts a suggestion (`%{kind, id}`) as a plan in the match's conversation
  through `PartnerMatches.post_plan/3`, if it is still one of the match's
  suggestions.
  """
  def propose(context, match_id, params, now \\ DateTime.utc_now()) do
    with {:ok, wanted} <- wanted_key(params),
         {:ok, ranked} <- ranked(context, match_id, now),
         {:ok, suggestion} <- find(ranked, wanted),
         {:ok, message} <- post_plan(context, match_id, plan(suggestion)) do
      Suggestions.count(context, "proposed")
      {:ok, message}
    end
  end

  @doc "Records «Δεν ταιριάζει» (`%{key, reason}`) on a suggestion of the match."
  def feedback(%{user_id: user_id} = context, match_id, params, now \\ DateTime.utc_now()) do
    with {:ok, %{key: key, reason: reason}} <-
           Suggestions.check_feedback(%{key: param(params, :key), reason: param(params, :reason)}),
         {:ok, match, _other_id} <- own_match(context, match_id),
         {:ok, _feedback} <-
           Suggestions.put_feedback(
             context,
             %{match_id: match.id, user_id: user_id, suggestion_key: key, reason: reason},
             now
           ) do
      Suggestions.count(context, "feedback")
      {:ok, %{key: key, reason: reason}}
    end
  end

  # ---------------------------------------------------------------- platform

  @doc "The vendors' view: daily counters of the last #{@stats_days} days and feedback reasons."
  def stats(platform_context, now \\ DateTime.utc_now())

  def stats(%{vendor: vendor, user_id: user_id} = context, now)
      when not is_nil(vendor) and is_binary(user_id) do
    since = now |> DateTime.to_date() |> Date.add(-(@stats_days - 1))
    counters = Suggestions.list_counters(context, since)

    days =
      Enum.map(Date.range(since, DateTime.to_date(now)), fn day ->
        counts =
          counters
          |> Enum.filter(&(Date.compare(&1.day, day) == :eq))
          |> Map.new(&{&1.event, &1.count})

        Suggestions.events()
        |> Map.new(&{&1, Map.get(counts, &1, 0)})
        |> Map.put("day", day)
      end)

    reasons = Suggestions.feedback_reasons(context, DateTime.new!(since, ~T[00:00:00]))

    {:ok,
     %{
       since: since,
       days: days,
       feedback_reasons: Map.new(Suggestions.feedback_reasons(), &{&1, Map.get(reasons, &1, 0)})
     }}
  end

  def stats(_context, _now), do: {:error, :vendor_required}

  # ------------------------------------------------------------- the engine

  defp ranked(%{user_id: user_id} = context, match_id, now) do
    with {:ok, match, other_id} <- own_match(context, match_id) do
      if active?(match) do
        people = people(context, match.id, user_id, other_id)
        candidates = candidates(context, people, now)

        organisers =
          candidates |> Enum.map(& &1.organiser_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        {:ok,
         Suggestions.suggest(%{
           people: people,
           candidates: candidates,
           blocked_ids: Suggestions.blocked(context, match.id, organisers),
           now: now
         })}
      else
        {:ok, []}
      end
    end
  end

  # The viewer first, then the other person, as the engine expects.
  defp people(context, match_id, user_id, other_id) do
    facts = context |> Suggestions.pair(match_id) |> Map.new(&{&1.user_id, &1})

    Enum.map([user_id, other_id], fn id ->
      fact = Map.get(facts, id, %{})

      %{
        id: id,
        level: Map.get(fact, :level),
        times: Map.get(fact, :times, []),
        point: Map.get(fact, :point),
        max_km: Suggestions.default_km()
      }
    end)
  end

  defp candidates(context, [me, other] = people, now) do
    window = Suggestions.window(now)
    shared = Suggestions.shared_organizations(context, me.id, other.id)
    classes = Enum.flat_map(shared, &box_classes(&1, people, window))

    if is_nil(me.point) or is_nil(other.point) do
      classes
    else
      area =
        Places.circle(
          [me.point, other.point],
          max(me.max_km, other.max_km) * 1000
        )

      classes ++
        events(context, people, area, now) ++
        trials(context, people, area, shared, window, now)
    end
  end

  # -- classes of a box both belong to

  defp box_classes(organization_id, [me, _other] = people, {from, to}) do
    scope = %{organization_id: organization_id, user_id: me.id}
    slots = Scheduling.get_calendar_week(scope, %{start_at: from, end_at: to})
    locations = locations(scope)
    time_zone = Organizations.organization_timezone(organization_id)
    box_name = box_name(me.id, organization_id)

    Enum.map(slots, fn slot ->
      location = Map.get(locations, slot.location_id) || first_location(locations)

      slot
      |> slot_candidate("class", people, time_zone)
      |> Map.merge(%{
        point: location_point(location),
        place: (location && location.name) || box_name,
        capacity_left: slot.spots_remaining
      })
    end)
  end

  # -- events near both, from Γύρω μου

  defp events(%{user_id: user_id} = context, [_me, other], area, now) do
    with {:ok, plan} <- around_plan(user_id, %{"kinds" => ["events"]}, now) do
      {rows, _total} = Places.search(context, "events", area, plan, nil, @event_limit)
      points = Map.new(rows, &{&1.id, point(&1.latitude, &1.longitude)})

      events =
        rows
        |> Enum.group_by(& &1.organization_id, & &1.id)
        |> Enum.flat_map(fn {organization_id, ids} ->
          Community.list_events(%{organization_id: organization_id, user_id: user_id}, %{
            organization_ids: [organization_id],
            ids: ids
          })
        end)

      other_going = other_going(user_id, other.id, events)

      context
      |> CommunityEvents.present_cards(events, now)
      |> Enum.map(fn card ->
        mine = card.my && card.my.status == "going"

        %{
          kind: "event",
          id: card.id,
          title: card.title,
          starts_at: card.starts_at,
          ends_at: card.ends_at,
          time_zone: card.time_zone,
          point: Map.get(points, card.id) || place_point(card.place),
          place: card.place && card.place.name,
          level: nil,
          capacity_left: card.spots_left,
          cancelled: card.cancelled,
          organiser_id: event_organiser(card.host),
          booked_by:
            Enum.reject(
              [if(mine, do: user_id), if(MapSet.member?(other_going, card.id), do: other.id)],
              &is_nil/1
            )
        }
      end)
    else
      _error -> []
    end
  end

  defp other_going(user_id, other_id, events) do
    ids = MapSet.new(events, & &1.id)

    events
    |> Enum.map(& &1.organization_id)
    |> Enum.uniq()
    |> Enum.flat_map(fn organization_id ->
      Community.attendances_of(
        %{organization_id: organization_id, user_id: user_id},
        other_id,
        ["going"]
      )
    end)
    |> Enum.map(& &1.event_id)
    |> Enum.filter(&MapSet.member?(ids, &1))
    |> MapSet.new()
  end

  defp event_organiser(%{kind: "person", person: %{id: id}}), do: id
  defp event_organiser(_host), do: nil

  # -- trial classes of boxes near both that neither belongs to

  defp trials(%{user_id: user_id} = context, [_me, other] = people, area, shared, window, now) do
    with {:ok, plan} <- around_plan(user_id, %{"kinds" => ["boxes"], "cost" => ["trial"]}, now) do
      {rows, _total} = Places.search(context, "boxes", area, plan, nil, @trial_box_limit)

      rows
      |> Enum.reject(&(&1.organization_id in shared))
      |> Enum.flat_map(&box_trials(&1, people, user_id, other.id, window, now))
    else
      _error -> []
    end
  end

  defp box_trials(row, people, user_id, other_id, {from, to}, now) do
    organization_id = row.organization_id
    scope = %{organization_id: organization_id, user_id: user_id}
    slots = Scheduling.get_calendar_week(scope, %{start_at: from, end_at: to})

    with [_ | _] <- slots,
         %{blocked_reason: nil, seats: mine} <-
           Trials.offer(organization_id, user_id, slots, now),
         %{blocked_reason: nil, seats: theirs} <-
           Trials.offer(organization_id, other_id, slots, now) do
      time_zone = Organizations.organization_timezone(organization_id)

      Enum.flat_map(slots, fn slot ->
        case {Map.get(mine, slot.id), Map.get(theirs, slot.id)} do
          {a, b} when is_integer(a) and is_integer(b) ->
            [
              slot
              |> slot_candidate("trial", people, time_zone)
              |> Map.merge(%{
                point: point(row.latitude, row.longitude),
                place: row.name,
                capacity_left: Enum.min([a, b, slot.spots_remaining])
              })
            ]

          _not_open ->
            []
        end
      end)
    else
      _none -> []
    end
  end

  defp around_plan(user_id, filter, now) do
    with {:ok, filter} <- Places.parse_filter(filter, AroundMe.vocabulary()) do
      {:ok, Places.plan(filter, AroundMe.viewer(user_id), now, :list)}
    end
  end

  # -- shared shapes

  defp slot_candidate(slot, kind, people, time_zone) do
    pair = Enum.map(people, & &1.id)

    %{
      kind: kind,
      id: slot.id,
      title: slot_title(slot),
      starts_at: slot.scheduled_at,
      ends_at: DateTime.add(slot.scheduled_at, (slot.duration_minutes || 60) * 60, :second),
      time_zone: time_zone,
      level: slot.class_type && slot.class_type.level,
      cancelled: not is_nil(slot.cancelled_at) or not is_nil(Map.get(slot, :paused_at)),
      organiser_id: slot.coach_user_id,
      booked_by:
        slot
        |> Map.get(:bookings, [])
        |> Enum.filter(&(&1.user_id in pair and &1.status in @booked_statuses))
        |> Enum.map(& &1.user_id)
    }
  end

  defp slot_title(%{name: name}) when is_binary(name) and name != "", do: name
  defp slot_title(%{class_type: %{name: name}}), do: name
  defp slot_title(_slot), do: nil

  defp locations(scope) do
    scope
    |> Facility.list_locations()
    |> Enum.filter(&is_nil(Map.get(&1, :archived_at)))
    |> Map.new(&{&1.id, &1})
  end

  defp first_location(locations) do
    locations
    |> Map.values()
    |> Enum.sort_by(&{is_nil(location_point(&1)), to_string(&1.name), &1.id})
    |> List.first()
  end

  defp location_point(nil), do: nil
  defp location_point(location), do: point(location.latitude, location.longitude)

  defp place_point(%{latitude: latitude, longitude: longitude}), do: point(latitude, longitude)
  defp place_point(_place), do: nil

  defp point(latitude, longitude) when is_number(latitude) and is_number(longitude),
    do: {latitude * 1.0, longitude * 1.0}

  defp point(_latitude, _longitude), do: nil

  defp box_name(user_id, organization_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.find_value(fn %{organization: organization} ->
      if organization.id == organization_id, do: organization.name
    end)
  end

  defp present(suggestion, user_id) do
    %{
      key: suggestion.key,
      kind: suggestion.kind,
      id: suggestion.id,
      title: suggestion.title,
      starts_at: suggestion.starts_at,
      ends_at: suggestion.ends_at,
      time_zone: suggestion.time_zone,
      place: suggestion.place,
      spots_left: suggestion.capacity_left,
      booked_by_me: user_id in suggestion.booked_by,
      booked_by_partner: Enum.any?(suggestion.booked_by, &(&1 != user_id)),
      distances_km: suggestion.distances_km,
      reasons: suggestion.reasons
    }
  end

  defp plan(suggestion) do
    %{
      kind: suggestion.kind,
      id: suggestion.id,
      title: suggestion.title,
      starts_at: suggestion.starts_at,
      place: suggestion.place
    }
  end

  defp wanted_key(params) do
    kind = param(params, :kind)
    id = param(params, :id)

    if is_binary(kind) and is_binary(id),
      do: {:ok, Suggestions.key(%{kind: kind, id: id})},
      else: {:error, :invalid_partner_suggestion_key}
  end

  defp find(ranked, key) do
    case Enum.find(ranked, &(&1.key == key)) do
      nil -> {:error, :partner_suggestion_unavailable}
      suggestion -> {:ok, suggestion}
    end
  end

  defp active?(match), do: to_string(Map.get(match, :status, "active")) == "active"

  # The match side (ADR-280 seams) lives in PartnerMatches; `apply/3` keeps
  # this module compiling while that side is merged separately.
  defp own_match(context, match_id), do: apply(@matches, :own_match, [context, match_id])

  defp post_plan(context, match_id, plan),
    do: apply(@matches, :post_plan, [context, match_id, plan])

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil
end
