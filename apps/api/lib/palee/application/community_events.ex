defmodule Palee.Application.CommunityEvents do
  @moduledoc """
  Club events from the member app (ADR-153, board 8), read and written from
  the person's own session:

  * **Lists.** A club's upcoming and past events, the upcoming events of
    every club the person can see, their own events (going or waiting) at
    any box, and a box page's events open to everyone.
  * **«Θα έρθω» / «Δεν θα έρθω».** Club members, anyone signed in on an open
    event, and guests holding a going member's invitation. A freed place
    goes to the waitlist and its new holder hears about it.
  * **Guest pass.** A going member gets a signed link (`EventInvites`).
  * **Running events.** Whoever holds `manage_events` at the box (staff and
    coaches) creates, edits and cancels from the club page too; the same
    `manage_*` functions serve «Κοινότητα» (`StaffCommunityEvents`).

  Every write runs in the scope of the gym that runs the club. Publishing an
  event posts its card in the club's #ανακοινώσεις; changes and
  cancellations reach the people going.

  ADR-185: a person's own event (an organiser organisation's) posts its card
  to the host's followers instead, when it is open to everyone; boxes that
  co-host an event list it with their own; the host's own invitation link
  needs no guest pass; events of a host the person blocked never show; and
  opening an event page counts a view (aggregated, deduped per day).
  """

  alias Palee.Application.{
    BoxPhotoCovers,
    ClassLocation,
    ClubScope,
    CommunityPeople,
    EventInvites,
    EventNotices,
    EventPresenter,
    GoLive,
    KeyDerivation,
    PublicBox,
    RealtimePublisher
  }

  alias Palee.{Community, Identity, Organizations}

  @past_limit 50
  @upcoming_limit 100

  # ------------------------------------------------------------------ lists

  @doc "A club's events: `scope` `upcoming` (default, cancelled ones flagged) or `past`."
  def club_events(context, club_id, params, now \\ DateTime.utc_now()) do
    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, club} <- find_club(clubs, club_id) do
      filter = Map.merge(%{club_ids: [club.id]}, window(params[:scope], now))

      events =
        context
        |> gym_of(club.organization_id)
        |> Community.list_events(filter)
        |> Kernel.++(
          if club.kind == "gym", do: cohosted(context, [club.organization_id], filter), else: []
        )
        |> visible_only(context, clubs)
        |> sort_window(params[:scope])

      {:ok, %{events: present(context, events, clubs, now: now)}}
    end
  end

  @doc "Upcoming events of every club the person can see."
  def clubs_events(context, now \\ DateTime.utc_now()) do
    with {:ok, clubs} <- ClubScope.call(context) do
      events =
        clubs
        |> Enum.group_by(& &1.organization_id, & &1.id)
        |> Enum.flat_map(fn {organization_id, club_ids} ->
          Community.list_events(gym(organization_id, context), %{
            club_ids: club_ids,
            from: now,
            limit: @upcoming_limit
          })
        end)
        |> Kernel.++(
          cohosted(context, gym_organization_ids(clubs), %{from: now, limit: @upcoming_limit})
        )
        |> Enum.uniq_by(& &1.id)
        |> visible_only(context, clubs)
        |> sort()

      {:ok, %{events: present(context, events, clubs, now: now)}}
    end
  end

  @doc "The person's upcoming events at any box: where they are going or waiting."
  def my_events(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    with {:ok, clubs} <- ClubScope.call(context) do
      events =
        %{user_id: user_id}
        |> Community.attendances_of(user_id, ~w(going waitlisted))
        |> Enum.group_by(& &1.organization_id, & &1.event_id)
        |> Enum.flat_map(fn {organization_id, ids} ->
          Community.list_events(gym(organization_id, context), %{
            organization_ids: [organization_id],
            ids: ids,
            from: now,
            include_cancelled: true
          })
        end)
        |> sort()

      {:ok, %{events: present(context, events, clubs, now: now)}}
    end
  end

  @doc "A published box's upcoming events open to everyone (its page's Events tab)."
  def box_events(context, slug, now \\ DateTime.utc_now()) do
    with {:ok, box, _scope} <- PublicBox.resolve(slug),
         {:ok, clubs} <- ClubScope.call(context) do
      window = %{open_only: true, from: now, limit: @upcoming_limit}

      events =
        gym(box.organization_id, context)
        |> Community.list_events(Map.put(window, :organization_ids, [box.organization_id]))
        |> Kernel.++(cohosted(context, [box.organization_id], window))
        |> Enum.uniq_by(& &1.id)
        |> without_blocked_hosts(context)
        |> sort()

      {:ok, %{events: present(context, events, clubs, now: now)}}
    end
  end

  @doc """
  One event, with everyone going by name for people who can see the club.
  With `invite_token`, also who invited the person and whether the
  invitation still has a place.
  """
  def show(%{user_id: user_id} = context, event_id, invite_token \\ nil) do
    now = DateTime.utc_now()

    with {:ok, event, clubs, invite} <- locate(context, event_id, invite_token) do
      [shown] = present(context, [event], clubs, goers: :all, now: now)
      gym = gym(event.organization_id, context)

      {:ok,
       shown
       |> Map.put(:invitation, invite && invitation(gym, event, invite, now))
       |> Map.put(:guests_left, guests_left(gym, event, user_id))}
    end
  end

  # ------------------------------------------------------------------ places

  @doc "«Θα έρθω» (`going: true`) or «Δεν θα έρθω» (`going: false`)."
  def rsvp(%{user_id: user_id} = context, event_id, params) do
    now = DateTime.utc_now()

    with {:ok, event, clubs, invite} <- locate(context, event_id, params[:invite_token]) do
      gym = gym(event.organization_id, context)

      invited_by = invite && invite.inviter_id != user_id && invite.inviter_id

      result =
        if params[:going] do
          rsvp_live(event, user_id, fn ->
            Community.rsvp_event(
              gym,
              event.id,
              user_id,
              %{
                club_member?: EventPresenter.belongs?(event, viewer(context, clubs)),
                invited_by: invited_by,
                host_invite?: is_binary(invited_by) and host?(invited_by, event)
              },
              now
            )
          end)
        else
          Community.withdraw_from_event(gym, event.id, user_id, user_id, now)
        end

      with {:ok, outcome} <- result do
        after_rsvp(event, outcome, user_id)
        announce(event)
        show(context, event.id, params[:invite_token])
      end
    end
  end

  # ADR-184: a business in demo mode takes no places from real people.
  defp rsvp_live(event, user_id, rsvp) do
    case GoLive.check_booking_at(event.organization_id, user_id) do
      :ok -> rsvp.()
      error -> error
    end
  end

  defp after_rsvp(event, %{joined: true, attendee: %{source: "guest"} = attendee}, user_id) do
    nickname = [user_id] |> CommunityPeople.by_ids() |> CommunityPeople.person(user_id)
    EventNotices.guest_joined(event, attendee.invited_by_id, user_id, nickname.nickname)
  end

  defp after_rsvp(event, %{promoted: [_ | _] = promoted}, _user_id),
    do: EventNotices.promoted(event, promoted)

  defp after_rsvp(_event, _outcome, _user_id), do: :ok

  @doc """
  A going member's guest pass link for the event; for whoever runs it, the
  host's own invitation link (no guest pass, no limit; ADR-185).
  """
  def invite(%{user_id: user_id} = context, event_id) do
    now = DateTime.utc_now()

    with {:ok, event, _clubs, _invite} <- locate(context, event_id, nil),
         # ADR-184: no guest links out of a business in demo mode.
         :ok <- GoLive.check_at(event.organization_id, :invite_people),
         gym = gym(event.organization_id, context),
         :ok <- Community.event_open_for_rsvp(event, now) do
      if host?(user_id, event),
        do: host_invite(event, user_id),
        else: guest_pass(gym, event, user_id)
    end
  end

  defp host_invite(event, user_id) do
    with :ok <- Community.event_invite_check(event, :host, nil, 0) do
      token = EventInvites.sign(event, user_id)

      {:ok,
       %{
         token: token,
         path: EventInvites.path(event.id, token),
         guests_left: nil,
         host: true,
         expires_at: event.starts_at
       }}
    end
  end

  defp guest_pass(gym, event, user_id) do
    status = attendee_status(gym, event.id, user_id)
    guests = Community.count_guests(gym, event.id, user_id)

    with :ok <- Community.event_guest_check(event, status, guests) do
      token = EventInvites.sign(event, user_id)

      {:ok,
       %{
         token: token,
         path: EventInvites.path(event.id, token),
         guests_left: event.guests_per_member - guests,
         host: false,
         expires_at: event.starts_at
       }}
    end
  end

  @doc """
  ADR-185: counts an open of the event page, once per person and day for
  the distinct viewers (an HMAC of event, day and person under a server
  key; no person is stored). People who run the event are not counted.
  """
  def record_view(%{user_id: user_id} = context, event_id, now \\ DateTime.utc_now()) do
    with {:ok, event, _clubs, _invite} <- locate(context, event_id, nil) do
      host? = host?(user_id, event)

      unless host? do
        day = DateTime.to_date(now)
        key = KeyDerivation.derive("event-view", Enum.join([event.id, day, user_id], "|"))

        Community.record_event_view(
          gym(event.organization_id, context),
          event.id,
          day,
          binary_part(key, 0, 16)
        )
      end

      {:ok, %{counted: not host?}}
    end
  end

  # Whoever runs the event at its box (manage_events there), or a group's admin.
  defp host?(user_id, event), do: event.organization_id in managed(user_id)

  # ------------------------------------------------------------------ running events (member app)

  @doc "Creates an event in a club the person can see, if they run events at its box."
  def create(context, club_id, params) do
    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, club} <- find_club(clubs, club_id),
         {:ok, manager} <- event_manager(context, club.organization_id),
         {:ok, [first | _] = events} <- manage_create(manager, club, params) do
      [shown] = present(context, [first], clubs)
      {:ok, %{event: shown, occurrences: length(events)}}
    end
  end

  def update(context, event_id, params) do
    with {:ok, event, clubs, _invite} <- locate(context, event_id, nil),
         {:ok, manager} <- event_manager(context, event.organization_id),
         {:ok, updated} <- manage_update(manager, event, params) do
      [shown] = present(context, [updated], clubs)
      {:ok, shown}
    end
  end

  def cancel(context, event_id, params) do
    with {:ok, event, clubs, _invite} <- locate(context, event_id, nil),
         {:ok, manager} <- event_manager(context, event.organization_id),
         {:ok, cancelled} <- manage_cancel(manager, event, params) do
      [shown] = present(context, cancelled |> Enum.filter(&(&1.id == event.id)), clubs)
      {:ok, shown}
    end
  end

  # ------------------------------------------------------------------ shared with «Κοινότητα»

  @doc """
  Creates an event (or a weekly run of them) in `club` from a tenant context
  holding `manage_events`, and posts its card in the club's announcements.
  """
  def manage_create(%{organization_id: organization_id} = manager, club, params) do
    attrs = editable(params)

    zone =
      Community.event_time_zone(attrs, Organizations.organization_timezone(organization_id))

    with {:ok, channel} <- group_channel(manager, club, params[:channel_id]),
         :ok <- authorize_event(manager, channel),
         :ok <- ClassLocation.check(manager, attrs),
         :ok <- BoxPhotoCovers.ready(manager, attrs[:cover_media_id]),
         {:ok, events} <-
           Community.create_event(manager, club, attrs,
             repeat_until: params[:repeat_until],
             zone: zone,
             channel_id: channel && channel.id
           ),
         {:ok, events} <- publish_card(manager, club, channel, events) do
      [first | _] = events
      BoxPhotoCovers.settle(manager, nil, first.cover_media_id)
      announce(first)
      {:ok, events}
    end
  end

  @doc """
  Edits `event` (scope `this`, default) or it and every later occurrence
  (`following`). People going hear when the time or the place changed;
  people let in by a raised capacity hear that too.
  """
  def manage_update(%{organization_id: organization_id} = manager, event, params) do
    attrs = editable(params)
    now = DateTime.utc_now()

    # A repeat stays at the same local time on the clock it is planned on.
    zone =
      Community.event_time_zone(
        Map.merge(Map.take(event, [:time_zone]), Map.take(attrs, [:time_zone])),
        Organizations.organization_timezone(organization_id)
      )

    with :ok <- own_event(manager, event),
         :ok <- authorize_event(manager, event_channel(manager, event)),
         :ok <-
           if(Map.has_key?(attrs, :location_id),
             do: ClassLocation.check(manager, attrs),
             else: :ok
           ),
         :ok <- BoxPhotoCovers.ready(manager, attrs[:cover_media_id]),
         {:ok, results} <-
           Community.update_event(manager, event, attrs, params[:scope] || "this",
             zone: zone,
             now: now
           ) do
      Enum.each(results, fn %{before: earlier, after: later, promoted: promoted} ->
        changes = Community.event_notable_changes(earlier, later)

        if changes != [] and DateTime.compare(later.starts_at, now) == :gt do
          EventNotices.changed(later, others(manager, later, ["going", "waitlisted"]), changes)
        end

        EventNotices.promoted(later, promoted)
      end)

      settle_covers(manager, results)
      Enum.each(results, &announce(&1.after))
      edited = Enum.find(results, &(&1.after.id == event.id))

      # ADR-185: a person's event that opened to everyone reaches their followers.
      if not edited.before.open_to_non_members and edited.after.open_to_non_members and
           organiser_host?(manager),
         do: publish_profile_card(manager, [edited.after])

      {:ok, edited.after}
    end
  end

  @doc "Cancels `event` (scope `this`) or it and every later occurrence (`following`)."
  def manage_cancel(manager, event, params) do
    now = DateTime.utc_now()
    reason = blank_to_nil(params[:reason])

    with :ok <- own_event(manager, event),
         :ok <- authorize_event(manager, event_channel(manager, event)),
         {:ok, cancelled} <-
           Community.cancel_event(manager, event, params[:scope] || "this", reason, now) do
      Enum.each(cancelled, fn cancelled_event ->
        if DateTime.compare(cancelled_event.starts_at, now) == :gt do
          EventNotices.cancelled(
            cancelled_event,
            others(manager, cancelled_event, ["going", "waitlisted"])
          )
        end

        announce(cancelled_event)
      end)

      {:ok, cancelled}
    end
  end

  @doc "An event of the context's gym, or `{:error, :not_found}`."
  def fetch_own(%{organization_id: organization_id} = context, event_id) do
    case Community.get_event(context, event_id) do
      %{organization_id: ^organization_id} = event ->
        if in_staff_scope?(context, event),
          do: {:ok, event},
          else: {:error, :location_out_of_scope}

      _other ->
        {:error, :not_found}
    end
  end

  @doc """
  ADR-186: whether staff work this event: one at their branches, or (without
  a branch) when they work everywhere or created it themselves.
  """
  def in_staff_scope?(context, event) do
    case Map.get(event, :location_id) do
      nil ->
        Organizations.location_scope(context) == :all or
          Map.get(event, :created_by_id) == Map.get(context, :user_id)

      location_id ->
        Organizations.location_in_scope?(context, location_id)
    end
  end

  def announce(event),
    do:
      RealtimePublisher.broadcast("community:club:#{event.club_id}", "event_updated", %{
        event_id: event.id
      })

  # ------------------------------------------------------------------ internals

  # A club event's card goes in the club's announcements, a group event's in
  # the group; a person's own open event's card goes to their followers.
  defp publish_card(manager, club, group, events) do
    if organiser_host?(manager),
      do: publish_profile_card(manager, events),
      else: publish_club_card(manager, club, group, events)
  end

  defp organiser_host?(%{organization_id: organization_id}),
    do:
      Community.organiser?(
        Map.get(Organizations.provider_kinds([organization_id]), organization_id)
      )

  defp publish_profile_card(
         %{user_id: user_id},
         [%{open_to_non_members: true} = first | _] = events
       ) do
    with {:ok, _post} <-
           Community.create_profile_post(%{user_id: user_id}, "public", %{
             attachment_type: "event",
             attachment_id: first.id,
             attachment: %{
               "title" => first.title,
               "starts_at" => DateTime.to_iso8601(first.starts_at),
               "occurrences" => length(events),
               "organization_id" => first.organization_id
             }
           }),
         do: {:ok, events}
  end

  defp publish_profile_card(_manager, events), do: {:ok, events}

  defp publish_club_card(manager, club, group, [first | _] = events) do
    channel =
      group ||
        case Community.get_club(manager, club.id) do
          %{channels: channels} -> Enum.find(channels, &(&1.kind == "announcements"))
          nil -> nil
        end

    if channel do
      # The card is posted on behalf of whoever runs the event; holding
      # manage_events (or running the group) is the right to write there.
      with {:ok, post} <-
             Community.create_post(
               manager,
               channel,
               if(group, do: "member", else: "staff"),
               true,
               %{
                 audience: "club_channel",
                 attachment_type: "event",
                 attachment_id: first.id,
                 attachment: %{
                   "title" => first.title,
                   "starts_at" => DateTime.to_iso8601(first.starts_at),
                   "occurrences" => length(events)
                 }
               }
             ),
           {:ok, linked} <- link_post(manager, events, post.id) do
        RealtimePublisher.broadcast("community:club:#{club.id}", "post_created", %{
          post_id: post.id,
          channel_id: channel.id
        })

        {:ok, linked}
      end
    else
      {:ok, events}
    end
  end

  defp link_post(manager, events, post_id) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, done} ->
      case Community.link_event_post(manager, event, post_id) do
        {:ok, linked} -> {:cont, {:ok, [linked | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, linked} -> {:ok, Enum.reverse(linked)}
      error -> error
    end
  end

  # Replaced covers are released once no event or open club of the box shows them.
  defp settle_covers(manager, results) do
    results
    |> Enum.map(&{&1.before.cover_media_id, &1.after.cover_media_id})
    |> Enum.uniq()
    |> Enum.each(fn {earlier, later} ->
      BoxPhotoCovers.settle(manager, earlier, later, &cover_in_use?(manager, &1))
    end)
  end

  defp cover_in_use?(%{organization_id: organization_id} = manager, media_id) do
    Community.list_events(manager, %{
      organization_ids: [organization_id],
      cover_media_id: media_id,
      include_cancelled: true,
      limit: 1
    }) != [] or
      manager
      |> Community.list_open_clubs(%{organization_ids: [organization_id], limit: 500})
      |> Enum.any?(&(&1.cover_media_id == media_id))
  end

  # Everyone on the event in `statuses` except whoever made the change.
  defp others(%{user_id: actor_id} = manager, event, statuses) do
    manager
    |> Community.list_attendees([event.id], statuses)
    |> Enum.reject(&(&1.user_id == actor_id))
  end

  @doc false
  # The event, the person's clubs, and their invitation to it (if any), when
  # the person may see it: they can see the club, it is open to everyone,
  # they are on it, or they hold an invitation to it.
  def locate(%{user_id: user_id} = context, event_id, invite_token) do
    invite =
      case EventInvites.verify(invite_token) do
        {:ok, %{event_id: ^event_id} = invite} -> invite
        _none -> nil
      end

    event =
      Community.get_event(%{user_id: user_id}, event_id) ||
        (invite && Community.get_event(gym(invite.organization_id, context), event_id))

    with %{} <- event || {:error, :not_found},
         true <- without_blocked_hosts([event], context) != [] || {:error, :not_found},
         {:ok, clubs} <- ClubScope.call(context) do
      viewer = viewer(context, clubs)

      visible? =
        EventPresenter.visible?(event, viewer, %{invited?: not is_nil(invite)}) or
          (not is_nil(
             Community.get_attendee(gym(event.organization_id, context), event.id, user_id)
           ) and EventPresenter.visible?(event, viewer, %{attendee?: true}))

      if visible?, do: {:ok, event, clubs, invite}, else: {:error, :not_found}
    end
  end

  defp invitation(gym, event, invite, now) do
    people = CommunityPeople.by_ids([invite.inviter_id])
    guests = Community.count_guests(gym, event.id, invite.inviter_id)
    inviter = if host?(invite.inviter_id, event), do: :host, else: :guest_pass

    check =
      with :ok <- Community.event_open_for_rsvp(event, now),
           do:
             Community.event_invite_check(
               event,
               inviter,
               attendee_status(gym, event.id, invite.inviter_id),
               guests
             )

    %{
      inviter: CommunityPeople.person(people, invite.inviter_id),
      usable: check == :ok,
      reason:
        case check do
          :ok -> nil
          {:error, reason} -> Atom.to_string(reason)
        end
    }
  end

  defp guests_left(gym, %{guest_pass_allowed: true} = event, user_id) do
    if attendee_status(gym, event.id, user_id) == "going",
      do: max(event.guests_per_member - Community.count_guests(gym, event.id, user_id), 0)
  end

  defp guests_left(_gym, _event, _user_id), do: nil

  defp attendee_status(gym, event_id, user_id) do
    case Community.get_attendee(gym, event_id, user_id) do
      %{status: status} -> status
      nil -> nil
    end
  end

  @doc false
  # A tenant context at the box for someone running events from the member
  # app: their own roles there, checked for manage_events.
  def manager_context(%{user_id: user_id} = context, organization_id) do
    account = Map.get(context, :account) || Identity.find_by_id(user_id)

    with %{} <- account || {:error, :forbidden},
         {:ok, manager} <- Organizations.resolve_tenant_context_by_id(account, organization_id),
         :ok <- Organizations.authorize_capability(manager, Community.event_capability()) do
      {:ok, manager}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, _not_a_member} -> {:error, :forbidden}
    end
  end

  @doc """
  Events from any box as the person's cards (Γύρω μου, ADR-154): only those
  they may see, presented as everywhere else.
  """
  def present_cards(context, events, now \\ DateTime.utc_now())
  def present_cards(_context, [], _now), do: []

  def present_cards(context, events, now) do
    case ClubScope.call(context) do
      {:ok, clubs} ->
        events |> visible_only(context, clubs) |> then(&present(context, &1, clubs, now: now))

      _error ->
        []
    end
  end

  @doc false
  def present(%{user_id: user_id}, events, clubs, opts \\ []) do
    EventPresenter.present(events, viewer(%{user_id: user_id}, clubs), opts)
  end

  # Boxes where the person runs events (role defaults; manage_events is not grantable).
  defp managed(user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.filter(fn %{membership: membership} ->
      roles = Map.get(membership, :roles) || [membership.role]

      roles
      |> Organizations.capabilities_for(Map.get(membership, :coach_scope), %{})
      |> Map.has_key?(Community.event_capability())
    end)
    |> Enum.map(& &1.organization.id)
  end

  # The member group an event goes in (`channel_id` given), which must be an
  # active group of the club.
  defp group_channel(_manager, _club, nil), do: {:ok, nil}

  defp group_channel(manager, club, channel_id) do
    with %{} = channel <- Community.get_channel(manager, channel_id) || {:error, :not_found},
         :ok <- Community.event_group_channel_check(channel, club.id),
         do: {:ok, channel}
  end

  defp event_channel(_manager, %{channel_id: nil}), do: nil
  defp event_channel(manager, %{channel_id: id}), do: Community.get_channel(manager, id)

  # Staff and coaches run every event of their box; a group's admin those of
  # their group (EventPolicy.manage_check/2).
  defp authorize_event(manager, channel) do
    Community.event_manage_check(
      %{
        manage_events?:
          Organizations.authorize_capability(manager, Community.event_capability()) == :ok,
        group_admin?: not is_nil(channel) and group_admin?(manager, channel)
      },
      channel && channel.id
    )
  end

  defp group_admin?(%{user_id: user_id} = manager, channel) do
    membership =
      manager |> Community.channel_memberships_of(user_id, [channel.id]) |> Map.get(channel.id)

    Community.event_group_admin?(
      channel,
      membership && %{member?: Community.group_member?(membership), role: membership.role}
    )
  end

  # Whoever runs an event from the member app: their staff context at the box
  # when they hold manage_events, else their own session in the box's scope
  # (a group's admin); the manage_* functions decide.
  defp event_manager(context, organization_id) do
    case manager_context(context, organization_id) do
      {:ok, manager} -> {:ok, manager}
      {:error, :forbidden} -> {:ok, gym(organization_id, context)}
    end
  end

  defp own_event(%{organization_id: organization_id}, %{organization_id: organization_id}),
    do: :ok

  defp own_event(_context, _event), do: {:error, :not_found}

  defp find_club(clubs, club_id) do
    case Enum.find(clubs, &(&1.id == club_id)) do
      nil -> {:error, :not_found}
      club -> {:ok, club}
    end
  end

  defp viewer(%{user_id: user_id}, clubs),
    do: EventPresenter.viewer(user_id, clubs, managed(user_id))

  defp visible_only(events, context, clubs) do
    viewer = viewer(context, clubs)

    events
    |> Enum.filter(&EventPresenter.visible?(&1, viewer))
    |> without_blocked_hosts(context)
  end

  @doc false
  # ADR-185: a person's own events are hidden from people they blocked or
  # who blocked them (Community.blocked_user_ids/1, both ways).
  def without_blocked_hosts([], _context), do: []

  def without_blocked_hosts(events, %{user_id: user_id}) do
    blocked = MapSet.new(Community.blocked_user_ids(%{user_id: user_id}))

    if MapSet.size(blocked) == 0 do
      events
    else
      suspects = Enum.filter(events, &MapSet.member?(blocked, &1.created_by_id))

      kinds =
        suspects
        |> Enum.map(& &1.organization_id)
        |> Enum.uniq()
        |> Organizations.provider_kinds()

      Enum.reject(events, fn event ->
        MapSet.member?(blocked, event.created_by_id) and
          Community.organiser?(Map.get(kinds, event.organization_id))
      end)
    end
  end

  # ADR-185: events other boxes host and these boxes co-host (accepted),
  # read in the person's session (the co-host read policy), within `window`.
  defp cohosted(_context, [], _window), do: []

  defp cohosted(%{user_id: _} = context, organization_ids, window) do
    context
    |> Community.accepted_event_cohosts(nil, organization_ids)
    |> Enum.group_by(& &1.host_organization_id, & &1.event_id)
    |> Enum.flat_map(fn {host_id, ids} ->
      host_id
      |> gym(context)
      |> Community.list_events(
        window
        |> Map.take([:from, :ended_before, :order, :limit, :include_cancelled, :open_only])
        |> Map.merge(%{organization_ids: [host_id], ids: Enum.uniq(ids)})
      )
    end)
  end

  defp gym_organization_ids(clubs),
    do: clubs |> Enum.filter(&(&1.kind == "gym")) |> Enum.map(& &1.organization_id) |> Enum.uniq()

  defp sort_window(events, "past"),
    do: events |> sort() |> Enum.reverse() |> Enum.take(@past_limit)

  defp sort_window(events, _upcoming), do: events |> sort() |> Enum.take(@upcoming_limit)

  defp gym_of(context, organization_id), do: gym(organization_id, context)

  defp gym(organization_id, %{user_id: user_id}),
    do: %{organization_id: organization_id, user_id: user_id}

  defp window("past", now),
    do: %{ended_before: now, order: :desc, limit: @past_limit, include_cancelled: true}

  defp window(_upcoming, now), do: %{from: now, include_cancelled: true, limit: @upcoming_limit}

  defp sort(events), do: Enum.sort_by(events, &{&1.starts_at, &1.id}, &(compare(&1, &2) != :gt))

  defp compare({at_a, id_a}, {at_b, id_b}) do
    case DateTime.compare(at_a, at_b) do
      :eq -> if(id_a <= id_b, do: :lt, else: :gt)
      other -> other
    end
  end

  defp editable(params) do
    Community.event_editable_fields()
    |> Enum.filter(&Map.has_key?(params, &1))
    |> Map.new(&{&1, Map.get(params, &1)})
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))
end
