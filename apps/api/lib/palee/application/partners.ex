defmodule Palee.Application.Partners do
  @moduledoc """
  Public Partners (ADR-280, ADR-169, vision §7.3): one account-level profile
  per person, one deck for all of Palee, swiping and undo, the Ρυθμίσεις
  switch, reporting a person, and the Palee team's reports queue.

  Who may take part is the verification side's word on every call
  (`PartnerEligibility`): the viewer must be verified, and everyone shown
  is verified and not suspended. Nobody blocked either way ever shows, and
  mock people of a demo business reach only its staff (ADR-184). Rows are
  personal: every call runs in the acting person's own session.
  """

  alias Palee.Application.{
    CommunityPeople,
    PartnerEligibility,
    PartnerMatches,
    PartnerRealtime,
    PeopleBlocks
  }

  alias Palee.{Community, Identity, Notifications, Organizations, Partners, Places}

  # ------------------------------------------------------------- overview

  @doc "Partners as it applies to the viewer: eligibility, their profile, the options."
  def overview(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    eligibility = PartnerEligibility.status(context)
    profile = Partners.get_profile(context, user_id)
    used = Partners.count_swipes_since(context, user_id, Partners.swipe_window_start(now))

    {:ok,
     %{
       eligibility: present_eligibility(eligibility),
       profile: profile && present_profile(profile),
       swipes_remaining: Partners.swipes_remaining(used),
       distance: distance(user_id),
       options: options()
     }}
  end

  # «Απόσταση» needs the viewer's own «Η περιοχή μου» (neighbourhood
  # centroids only, never live location).
  defp distance(user_id) do
    if Places.home_area(%{user_id: user_id}) != [], do: "available", else: "needs_area"
  end

  @doc """
  Creates or updates the viewer's profile. Only a verified person; the first
  save needs `adult_confirmed: true` (ADR-280).
  """
  def put_profile(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- PartnerEligibility.require_verified(context),
         current = Partners.get_profile(context, user_id),
         {:ok, attrs} <-
           Partners.normalize_profile(params, current, Organizations.box_disciplines()),
         {:ok, confirmed_at} <- Partners.adult_confirmation(current, params, now),
         {:ok, profile} <- save_profile(context, user_id, current, attrs, confirmed_at) do
      {:ok, present_profile(profile)}
    end
  end

  defp save_profile(context, user_id, nil, attrs, confirmed_at),
    do:
      Partners.create_profile(
        context,
        Map.merge(attrs, %{user_id: user_id, adult_confirmed_at: confirmed_at})
      )

  defp save_profile(context, _user_id, current, attrs, _confirmed_at),
    do: Partners.update_profile(context, current, attrs)

  # ------------------------------------------------------------- the deck

  @doc "The next cards of the public deck, best fit first."
  def deck(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- PartnerEligibility.require_verified(context),
         {:ok, viewer} <- live_profile(context, user_id) do
      excluded = excluded_ids(context, user_id, now)
      filters = Partners.deck_filters(params)

      candidates =
        Partners.list_live_profiles(context, [user_id | MapSet.to_list(excluded)])

      allowed =
        candidates
        |> Enum.map(& &1.user_id)
        # ADR-184: mock people only ever reach their demo business's staff.
        |> Identity.visible_user_ids(user_id)
        |> PartnerEligibility.verified_user_ids()
        |> within(user_id, filters.within_km)
        |> MapSet.new()

      cards =
        Partners.deck(
          viewer,
          Enum.filter(candidates, &MapSet.member?(allowed, &1.user_id)),
          excluded,
          filters
        )

      ids = Enum.map(cards, fn {profile, _shared} -> profile.user_id end)
      people = CommunityPeople.by_ids(ids)
      badges = PartnerEligibility.verification_badges(ids)
      used = Partners.count_swipes_since(context, user_id, Partners.swipe_window_start(now))

      {:ok,
       %{
         cards: Enum.map(cards, &present_card(&1, people, badges)),
         swipes_remaining: Partners.swipes_remaining(used),
         within_km: filters.within_km
       }}
    end
  end

  # «Απόσταση» narrows the deck to people whose neighbourhood is near the
  # viewer's; without an area of their own nothing is narrowed.
  defp within(ids, _user_id, nil), do: ids
  defp within([], _user_id, _km), do: []

  defp within(ids, user_id, km) do
    if distance(user_id) == "available",
      do: Places.people_within(%{user_id: user_id}, ids, km * 1000),
      else: ids
  end

  @doc """
  A like or a pass. A like answered by a like makes the match (or returns
  the pair's existing one) and tells both people once.
  """
  def swipe(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- PartnerEligibility.require_verified(context),
         {:ok, direction} <- Partners.normalize_direction(param(params, "direction")),
         {:ok, target_id} <- cast_id(param(params, "target_id")),
         {:ok, viewer} <- live_profile(context, user_id),
         {:ok, _target} <- swipeable(context, viewer, target_id),
         :ok <- rate(context, user_id, now),
         {:ok, result} <-
           Partners.record_swipe(
             context,
             %{swiper_id: user_id, target_id: target_id, direction: direction},
             &Partners.mutual?(direction, &1),
             now
           ) do
      if result.new_match, do: matched(result.match)
      used = Partners.count_swipes_since(context, user_id, Partners.swipe_window_start(now))

      {:ok,
       %{
         target_id: target_id,
         direction: direction,
         match: result.match && PartnerMatches.present_summary(context, result.match),
         swipes_remaining: Partners.swipes_remaining(used)
       }}
    end
  end

  @doc "Takes back a swipe that made no match."
  def undo(%{user_id: user_id} = context, target_id) do
    with {:ok, target_id} <- cast_id(target_id),
         nil <- Partners.active_match_between(context, user_id, target_id),
         count when count > 0 <- Partners.delete_swipe(context, user_id, target_id) do
      {:ok, %{target_id: target_id, undone: true}}
    else
      %{id: _match_id} -> {:error, :partner_already_matched}
      0 -> {:error, :not_found}
      error -> error
    end
  end

  # ------------------------------------------------------------- settings

  @doc "Ρυθμίσεις: whether the viewer shows in the deck."
  def settings(%{user_id: user_id} = context) do
    {:ok, settings_of(Partners.get_profile(context, user_id))}
  end

  @doc """
  Ρυθμίσεις switch: off pauses the profile (out of the deck at once), on
  resumes it. Resuming needs a verified, not suspended person; opting in
  the first time happens with the profile.
  """
  def put_settings(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, visible} <- boolean(param(params, "visible")),
         :ok <- if(visible, do: PartnerEligibility.require_verified(context), else: :ok) do
      case Partners.get_profile(context, user_id) do
        nil ->
          {:ok, settings_of(nil)}

        profile ->
          changes =
            profile
            |> Partners.pause_changes(visible, now)
            |> then(&if(visible, do: Map.put(&1, :active, true), else: &1))

          with {:ok, profile} <- Partners.update_profile(context, profile, changes),
               do: {:ok, settings_of(profile)}
      end
    end
  end

  defp settings_of(nil), do: %{visible: false, has_profile: false}

  defp settings_of(profile),
    do: %{visible: Partners.profile_live?(profile), has_profile: true}

  # ------------------------------------------------------------- reports

  @doc """
  Reports a person (ADR-280): someone the reporter can reach (a live profile
  of the deck, or a match of theirs). Reporting also blocks them, so the
  two never meet again (ADR-169 §5); the Palee team decides.
  """
  def report(%{user_id: user_id} = context, params) do
    with {:ok, attrs} <- Partners.normalize_report(user_id, params),
         :ok <- reachable(context, user_id, attrs.target_id),
         {:ok, _report} <- Partners.insert_report(context, attrs),
         {:ok, _blocked} <- PeopleBlocks.block(context, attrs.target_id, "reported") do
      {:ok, %{target_id: attrs.target_id, reported: true, blocked: true}}
    end
  end

  defp reachable(context, user_id, target_id) do
    cond do
      not Identity.visible_to?(target_id, user_id) ->
        {:error, :not_found}

      Partners.get_profile(context, target_id) != nil ->
        :ok

      Enum.any?(Partners.list_matches(context, user_id), &Partners.match_party?(&1, target_id)) ->
        :ok

      true ->
        {:error, :not_found}
    end
  end

  @doc "The Palee team's queue (ADR-280): reports by status, newest first."
  def platform_reports(platform_context, params) do
    status = param(params, "status") || "open"

    if status in Partners.report_statuses() do
      reports = Partners.list_reports(platform_context, status)

      people =
        CommunityPeople.by_ids(Enum.flat_map(reports, &[&1.reporter_id, &1.target_id]))

      per_target = Enum.frequencies_by(reports, & &1.target_id)

      {:ok,
       %{
         reports:
           Enum.map(reports, &present_report(&1, people, Map.get(per_target, &1.target_id, 1)))
       }}
    else
      {:error, :invalid_partner_report_status}
    end
  end

  @doc """
  The Palee team decides a report, for every open report on that person:
  `suspend` (profile off, verification suspended, sponsors penalised,
  matches end with `suspended`) or `dismiss`.
  """
  def decide_report(
        %{user_id: vendor_id} = platform_context,
        report_id,
        params,
        now \\ DateTime.utc_now()
      ) do
    with {:ok, %{decision: decision, note: note}} <- Partners.normalize_report_decision(params),
         %{} = report <- Partners.get_report(platform_context, report_id) || {:error, :not_found},
         {:ok, changes} <-
           Partners.report_decision_changes(report, decision, vendor_id, note, now),
         {:ok, penalized} <- maybe_suspend(platform_context, report.target_id, decision, now) do
      decided = Partners.decide_reports(platform_context, report.target_id, changes)

      {:ok,
       %{
         id: report.id,
         target_id: report.target_id,
         decision: decision,
         resolved: length(decided),
         penalized_sponsors: length(penalized)
       }}
    end
  end

  defp maybe_suspend(platform_context, target_id, decision, now) do
    if Partners.report_suspends?(decision) do
      with {:ok, %{penalized_sponsor_ids: penalized}} <-
             PartnerEligibility.suspend(platform_context, target_id, now) do
        suspend_partners(platform_context, target_id, now)
        {:ok, penalized}
      end
    else
      {:ok, []}
    end
  end

  # The suspended person's profile goes off and every active match of theirs
  # ends (`suspended`, by nobody the other side knows).
  defp suspend_partners(platform_context, target_id, now) do
    case Partners.get_profile(platform_context, target_id) do
      nil ->
        :ok

      profile ->
        Partners.update_profile(platform_context, profile, Partners.suspension_profile_changes())
    end

    platform_context
    |> Partners.end_matches(%{user_id: target_id}, %{
      status: "ended",
      end_reason: Partners.suspension_end_reason(),
      ended_by_id: nil,
      ended_at: now
    })
    |> Enum.each(&PartnerRealtime.match_changed/1)

    :ok
  end

  # ------------------------------------------------------------- internals

  def options do
    %{
      levels: Partners.levels(),
      times: Partners.times(),
      goals: Partners.goals(),
      genders: Partners.genders(),
      gender_preferences: Partners.gender_preferences(),
      max_goals: Partners.max_goals(),
      disciplines: Organizations.box_disciplines(),
      max_disciplines: Partners.max_disciplines(),
      distances_km: Partners.distances_km(),
      default_within_km: Partners.default_within_km(),
      about_max: Partners.about_max(),
      daily_swipes: Partners.swipe_daily_limit(),
      report_reasons: Partners.report_reasons()
    }
  end

  defp present_eligibility(%{} = eligibility) do
    %{
      status: to_text(Map.get(eligibility, :status)),
      method: to_text(Map.get(eligibility, :method)),
      next_step: to_text(Map.get(eligibility, :next_step))
    }
  end

  defp to_text(nil), do: nil
  defp to_text(value) when is_atom(value), do: Atom.to_string(value)
  defp to_text(value), do: value

  defp live_profile(context, user_id) do
    case Partners.get_profile(context, user_id) do
      nil ->
        {:error, :partner_profile_required}

      profile ->
        if Partners.profile_live?(profile),
          do: {:ok, profile},
          else: {:error, :partner_profile_required}
    end
  end

  defp excluded_ids(context, user_id, now) do
    swiped = Partners.swiped_ids(Partners.list_swipes_by(context, user_id), now)

    swiped
    |> MapSet.union(MapSet.new(Community.blocked_user_ids(%{user_id: user_id})))
    |> MapSet.union(MapSet.new(Partners.active_partner_ids(context, user_id)))
  end

  # The deck's rules for one person, re-checked at the swipe: verified,
  # discoverable, live, compatible, not blocked either way.
  defp swipeable(context, viewer, target_id) do
    blocked = MapSet.new(Community.blocked_user_ids(%{user_id: viewer.user_id}))

    with true <- verified?(target_id) || {:error, :not_found},
         true <- Identity.visible_to?(target_id, viewer.user_id) || {:error, :not_found},
         %{} = target <- Partners.get_profile(context, target_id) || {:error, :not_found},
         true <- Partners.swipeable?(viewer, target, blocked) || {:error, :not_found} do
      {:ok, target}
    end
  end

  defp verified?(user_id),
    do: Enum.member?(PartnerEligibility.verified_user_ids([user_id]), user_id)

  defp rate(context, user_id, now),
    do:
      Partners.check_swipe_rate(
        Partners.count_swipes_since(context, user_id, Partners.swipe_window_start(now))
      )

  defp matched(match) do
    PartnerRealtime.match_changed(match)
    people = CommunityPeople.by_ids([match.user_a_id, match.user_b_id])

    for {user_id, other_id} <- [
          {match.user_a_id, match.user_b_id},
          {match.user_b_id, match.user_a_id}
        ] do
      Notifications.dispatch_event(:partner_match, %{
        user_id: user_id,
        match_id: match.id,
        partner_nickname: CommunityPeople.person(people, other_id).nickname,
        dedupe_key: "partner_match:#{match.id}:#{user_id}"
      })
    end

    :ok
  end

  @doc false
  def present_profile(profile) do
    %{
      id: profile.id,
      active: profile.active,
      paused: not is_nil(profile.paused_at),
      show_box: profile.show_box,
      adult_confirmed_at: profile.adult_confirmed_at,
      level: profile.level,
      times: profile.times,
      goals: profile.goals,
      disciplines: profile.disciplines,
      about: profile.about,
      gender: profile.gender,
      gender_preference: profile.gender_preference,
      updated_at: profile.updated_at
    }
  end

  defp present_card({profile, shared}, people, badges) do
    %{
      profile_id: profile.id,
      person: CommunityPeople.person(people, profile.user_id),
      badge: Partners.badge(Map.get(badges, profile.user_id), profile.show_box),
      level: profile.level,
      times: profile.times,
      goals: profile.goals,
      disciplines: profile.disciplines,
      about: profile.about,
      shared: shared
    }
  end

  defp present_report(report, people, open_on_target) do
    %{
      id: report.id,
      reporter: CommunityPeople.person(people, report.reporter_id),
      target: CommunityPeople.person(people, report.target_id),
      reason: report.reason,
      note: report.note,
      status: report.status,
      reports_on_target: open_on_target,
      decided_at: report.decided_at,
      decision_note: report.decision_note,
      created_at: report.inserted_at
    }
  end

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_value), do: {:error, :invalid_partners_visible}

  defp cast_id(id) do
    case Ecto.UUID.cast(id || "") do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end
