defmodule MilosTraining.Application.Partners do
  @moduledoc """
  Partners in one club (ADR-169, vision §7.3): the member's profile there,
  the deck, swiping and undo; also the Ρυθμίσεις switch across clubs and the
  report and staff sides of a profile.

  Eligibility is the gym's word on every call: the club must offer Partners
  (a verified club, the gym's switch on), the viewer and everyone shown must
  be members of the club right now and not hidden from members, and nobody
  blocked either way ever shows. Every write runs in the session of the
  club's gym.
  """

  alias MilosTraining.Application.{
    ClubMembers,
    ClubScope,
    CommunityPeople,
    PartnerMatches,
    PartnerRealtime
  }

  alias MilosTraining.{Community, Notifications, Partners}

  # ------------------------------------------------------------- the club

  @doc "Partners in a club as it applies to the viewer: offered?, their profile, the options."
  def overview(%{user_id: user_id} = context, club_id, now \\ DateTime.utc_now()) do
    with {:ok, club, scope} <- club(context, club_id) do
      offered = offered(club, scope)
      profile = Partners.get_profile(scope, club.id, user_id)
      used = Partners.count_swipes_since(scope, user_id, Partners.swipe_window_start(now))

      {:ok,
       %{
         club_id: club.id,
         offered: offered == :ok,
         unavailable_reason: unavailable_reason(offered),
         member: member?(scope, club, user_id),
         profile: profile && present_profile(profile),
         swipes_remaining: Partners.swipes_remaining(used),
         options: options()
       }}
    end
  end

  @doc "Creates or updates the viewer's profile in the club (opting in)."
  def put_profile(%{user_id: user_id} = context, club_id, params) do
    with {:ok, club, scope} <- club(context, club_id),
         :ok <- offered(club, scope),
         :ok <- member(scope, club, user_id),
         current = Partners.get_profile(scope, club.id, user_id),
         {:ok, attrs} <- Partners.normalize_profile(params, current),
         :ok <- Partners.check_activation(current || %{}, attrs.active),
         {:ok, profile} <- save_profile(scope, club, user_id, current, attrs) do
      {:ok, present_profile(profile)}
    end
  end

  defp save_profile(scope, club, user_id, nil, attrs),
    do: Partners.create_profile(scope, Map.merge(attrs, %{club_id: club.id, user_id: user_id}))

  defp save_profile(scope, _club, _user_id, current, attrs),
    do: Partners.update_profile(scope, current, attrs)

  @doc "The next cards of the deck, best fit first."
  def deck(%{user_id: user_id} = context, club_id, params, now \\ DateTime.utc_now()) do
    with {:ok, club, scope} <- club(context, club_id),
         :ok <- offered(club, scope),
         {:ok, viewer} <- live_profile(scope, club, user_id) do
      members = eligible_ids(scope, club) -- [user_id]
      excluded = excluded_ids(scope, club, user_id, now)
      candidates = Partners.list_live_profiles(scope, club.id, members)
      cards = Partners.deck(viewer, candidates, excluded, Partners.deck_filters(params))

      people =
        CommunityPeople.by_ids(Enum.map(cards, fn {profile, _shared} -> profile.user_id end))

      used = Partners.count_swipes_since(scope, user_id, Partners.swipe_window_start(now))

      {:ok,
       %{
         club_id: club.id,
         cards: Enum.map(cards, &present_card(&1, people)),
         swipes_remaining: Partners.swipes_remaining(used)
       }}
    end
  end

  @doc """
  A like or a pass. A like answered by a like makes the match (or returns
  the pair's existing one) and tells both people once.
  """
  def swipe(%{user_id: user_id} = context, club_id, params, now \\ DateTime.utc_now()) do
    with {:ok, club, scope} <- club(context, club_id),
         :ok <- offered(club, scope),
         {:ok, direction} <- Partners.normalize_direction(param(params, "direction")),
         {:ok, target_id} <- cast_id(param(params, "target_id")),
         {:ok, viewer} <- live_profile(scope, club, user_id),
         {:ok, target} <- swipeable(scope, club, viewer, target_id, now),
         :ok <- rate(scope, user_id, now),
         {:ok, result} <-
           Partners.record_swipe(
             scope,
             %{club_id: club.id, swiper_id: user_id, target_id: target_id, direction: direction},
             &Partners.mutual?(direction, &1),
             now
           ) do
      if result.new_match, do: matched(club, result.match)
      used = Partners.count_swipes_since(scope, user_id, Partners.swipe_window_start(now))

      {:ok,
       %{
         target_id: target_id,
         direction: direction,
         match:
           result.match && PartnerMatches.present_summary(context, club, result.match, target.id),
         swipes_remaining: Partners.swipes_remaining(used)
       }}
    end
  end

  @doc "Takes back a swipe that made no match."
  def undo(%{user_id: user_id} = context, club_id, target_id) do
    with {:ok, club, scope} <- club(context, club_id),
         {:ok, target_id} <- cast_id(target_id),
         nil <- Partners.active_match_between(scope, user_id, target_id),
         count when count > 0 <- Partners.delete_swipe(scope, club.id, user_id, target_id) do
      {:ok, %{target_id: target_id, undone: true}}
    else
      %{id: _match_id} -> {:error, :partner_already_matched}
      0 -> {:error, :not_found}
      error -> error
    end
  end

  # ------------------------------------------------------ across clubs

  @doc "Ρυθμίσεις: whether any profile is on, and in how many clubs one exists."
  def settings(context) do
    with {:ok, profiles} <- my_profiles(context) do
      {:ok, settings_of(profiles)}
    end
  end

  @doc """
  Ρυθμίσεις switch: off pauses every profile in every club at once; on
  resumes them (suspended ones stay off). Opting in the first time happens
  in a club.
  """
  def put_settings(%{user_id: user_id} = context, params) do
    with {:ok, visible} <- boolean(param(params, "visible")),
         {:ok, scopes} <- scopes(context) do
      Enum.each(scopes, &Partners.set_active_for_user(&1, user_id, visible))
      settings(context)
    end
  end

  defp settings_of(profiles) do
    %{
      visible: Enum.any?(profiles, &Partners.profile_live?/1),
      clubs: length(profiles),
      club_ids: Enum.map(profiles, & &1.club_id)
    }
  end

  defp my_profiles(%{user_id: user_id} = context) do
    with {:ok, scopes} <- scopes(context),
         do: {:ok, Enum.flat_map(scopes, &Partners.list_profiles_of(&1, user_id))}
  end

  @doc "One session per gym of the viewer's clubs (Partners rows are the gym's)."
  def scopes(context) do
    with {:ok, clubs} <- ClubScope.call(context) do
      {:ok,
       clubs
       |> Enum.map(& &1.organization_id)
       |> Enum.uniq()
       |> Enum.map(&%{organization_id: &1, user_id: context.user_id})}
    end
  end

  # ------------------------------------------------- reports and staff

  @doc """
  A report's target (ADR-169 §6): a profile in a club the reporter can reach,
  not their own. Returns the club as `ClubScope` presents it.
  """
  def report_target(context, profile_id) do
    with {:ok, clubs} <- ClubScope.reachable(context),
         {:ok, club, profile} <- find_profile(context, clubs, profile_id) do
      {:ok, club,
       %{
         type: "partner",
         id: profile.id,
         author_id: profile.user_id,
         club_id: club.id,
         channel_id: nil
       }}
    end
  end

  defp find_profile(context, clubs, profile_id) do
    clubs
    |> Enum.map(& &1.organization_id)
    |> Enum.uniq()
    |> Enum.find_value({:error, :not_found}, fn organization_id ->
      scope = %{organization_id: organization_id, user_id: context.user_id}

      with %{} = profile <- Partners.get_profile_by_id(scope, profile_id),
           %{} = club <- Enum.find(clubs, &(&1.id == profile.club_id)) do
        {:ok, club, profile}
      else
        _none -> nil
      end
    end)
  end

  @doc "What staff see of a reported profile in the queue."
  def report_preview(staff_context, profile_id) do
    case Partners.get_profile_by_id(staff_context, profile_id) do
      %{} = profile ->
        %{
          author_id: profile.user_id,
          body: profile.about,
          hidden: not is_nil(profile.suspended_at)
        }

      nil ->
        nil
    end
  end

  @doc """
  Staff hide a reported profile (ADR-169 §6): suspended in its club, out of
  every deck there, and its active matches in that club end.
  """
  def suspend(%{user_id: staff_id} = staff_context, profile_id, now \\ DateTime.utc_now()) do
    with %{} = profile <-
           Partners.get_profile_by_id(staff_context, profile_id) || {:error, :not_found},
         {:ok, _profile} <-
           Partners.update_profile(staff_context, profile, %{
             active: false,
             suspended_at: profile.suspended_at || now,
             suspended_by_id: staff_id
           }) do
      staff_context
      |> Partners.end_matches(%{club_id: profile.club_id, user_id: profile.user_id}, %{
        status: "ended",
        end_reason: "hidden",
        ended_by_id: staff_id,
        ended_at: now
      })
      |> Enum.each(&PartnerRealtime.match_changed/1)

      :ok
    end
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
      about_max: Partners.about_max(),
      daily_swipes: Partners.swipe_daily_limit()
    }
  end

  @doc false
  def club(context, club_id) do
    with {:ok, club} <- ClubScope.club(context, club_id),
         do: {:ok, club, ClubScope.write_context(club, context)}
  end

  @doc false
  def offered(club, scope),
    do:
      Partners.check_club(
        club,
        Map.get(Community.community_settings(scope), :partners_enabled, true)
      )

  defp unavailable_reason(:ok), do: nil
  defp unavailable_reason({:error, :partners_disabled}), do: "disabled"
  defp unavailable_reason({:error, _not_offered}), do: "not_offered"

  @doc "The club's members who may take part: members now, not hidden from members."
  def eligible_ids(scope, club) do
    ids = ClubMembers.member_ids(scope, club)
    ids -- Community.hidden_member_ids(ids)
  end

  defp member?(scope, club, user_id), do: user_id in ClubMembers.member_ids(scope, club)

  defp member(scope, club, user_id),
    do: if(member?(scope, club, user_id), do: :ok, else: {:error, :not_club_member})

  defp live_profile(scope, club, user_id) do
    with :ok <- member(scope, club, user_id) do
      case Partners.get_profile(scope, club.id, user_id) do
        nil ->
          {:error, :partner_profile_required}

        profile ->
          if Partners.profile_live?(profile),
            do: {:ok, profile},
            else: {:error, :partner_profile_required}
      end
    end
  end

  defp excluded_ids(scope, club, user_id, now) do
    swiped = Partners.swiped_ids(Partners.list_swipes_by(scope, club.id, user_id), now)

    swiped
    |> MapSet.union(MapSet.new(Community.blocked_user_ids(%{user_id: user_id})))
    |> MapSet.union(MapSet.new(Partners.active_partner_ids(scope, user_id)))
  end

  # The deck's rules for one person, re-checked at the swipe: still a
  # member, not hidden, live, compatible, not blocked or matched.
  defp swipeable(scope, club, viewer, target_id, _now) do
    blocked = MapSet.new(Community.blocked_user_ids(%{user_id: viewer.user_id}))

    with true <- target_id in eligible_ids(scope, club) || {:error, :not_found},
         %{} = target <- Partners.get_profile(scope, club.id, target_id) || {:error, :not_found},
         true <- Partners.swipeable?(viewer, target, blocked) || {:error, :not_found} do
      {:ok, target}
    end
  end

  defp rate(scope, user_id, now),
    do:
      Partners.check_swipe_rate(
        Partners.count_swipes_since(scope, user_id, Partners.swipe_window_start(now))
      )

  defp matched(club, match) do
    PartnerRealtime.match_changed(match)
    people = CommunityPeople.by_ids([match.user_a_id, match.user_b_id])

    for {user_id, other_id} <- [
          {match.user_a_id, match.user_b_id},
          {match.user_b_id, match.user_a_id}
        ] do
      Notifications.dispatch_event(:partner_match, %{
        user_id: user_id,
        organization_id: club.organization_id,
        match_id: match.id,
        club_id: club.id,
        club_name: club.name,
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
      club_id: profile.club_id,
      active: profile.active,
      suspended: not is_nil(profile.suspended_at),
      level: profile.level,
      times: profile.times,
      goals: profile.goals,
      about: profile.about,
      gender: profile.gender,
      gender_preference: profile.gender_preference,
      updated_at: profile.updated_at
    }
  end

  defp present_card({profile, shared}, people) do
    %{
      profile_id: profile.id,
      person: CommunityPeople.person(people, profile.user_id),
      level: profile.level,
      times: profile.times,
      goals: profile.goals,
      about: profile.about,
      shared: shared
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
