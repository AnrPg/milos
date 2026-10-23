defmodule Palee.Application.ClubScope do
  @moduledoc """
  The member's clubs as they apply to them (ADR-138, ADR-143): the club of
  every gym they actively belong to, the open clubs they joined (at any gym)
  and the open clubs of gyms where they are staff; their role in each, and
  each channel's governance for them. Shared by the club bar, the feed, posting
  and the realtime join.

  Member groups show to their members and to staff; a proposed one also to
  whoever proposed it. Declined groups never show here. A PT squad (ADR-168)
  shows only to its coach and to members whose coaching with that coach is
  still active, re-checked on every read; other invite-only channels to
  their participants and staff.
  """

  alias Palee.{Coaching, Community, Organizations}

  def call(%{user_id: user_id} = context) do
    memberships =
      user_id |> Organizations.list_memberships() |> Organizations.provider_memberships()

    by_organization = Map.new(memberships, &{&1.organization.id, &1})
    organization_ids = Map.keys(by_organization)

    with :ok <- ensure_clubs(context, organization_ids) do
      gym_clubs =
        context
        |> Community.list_clubs(organization_ids)
        |> Enum.filter(&(&1.kind == "gym"))

      open_clubs = open_clubs(context, user_id, by_organization)
      clubs = gym_clubs ++ open_clubs
      channel_ids = Enum.flat_map(clubs, fn club -> Enum.map(club.channels, & &1.id) end)
      channel_memberships = Community.channel_memberships_of(context, user_id, channel_ids)
      levels = Community.notify_levels(context, user_id, Enum.map(clubs, & &1.id))
      boxes = boxes(open_clubs, by_organization)
      coaches = squad_coaches(context, gym_clubs, channel_memberships)
      seen = {user_id, channel_memberships, coaches}

      presented =
        Enum.map(gym_clubs, fn club ->
          membership = by_organization[club.organization_id]
          role = Community.club_role(membership.membership)
          present(club, role, gym_face(club, membership), seen, levels)
        end) ++
          Enum.map(open_clubs, fn club ->
            present(
              club,
              club.role,
              open_face(club, by_organization, boxes),
              seen,
              levels
            )
          end)

      {:ok, Enum.sort_by(presented, &{&1.kind != "gym", String.downcase(&1.name || "")})}
    end
  end

  @doc "The one club of the context's gym, as it applies to the context's user."
  def gym_club(%{organization_id: organization_id} = context) do
    with {:ok, clubs} <- call(context) do
      case Enum.find(clubs, &(&1.organization_id == organization_id and &1.kind == "gym")) do
        nil -> {:error, :not_found}
        club -> {:ok, club}
      end
    end
  end

  @doc "Any club in the member's scope, by id."
  def club(context, club_id) do
    with {:ok, clubs} <- call(context) do
      case Enum.find(clubs, &(&1.id == club_id)) do
        nil -> {:error, :not_found}
        club -> {:ok, club}
      end
    end
  end

  @doc """
  The clubs a request may act on: a gym route (its context names the gym)
  reaches that gym's clubs; a personal route reaches all of them.
  """
  def reachable(%{organization_id: organization_id} = context) when is_binary(organization_id) do
    with {:ok, clubs} <- call(context),
         do: {:ok, Enum.filter(clubs, &(&1.organization_id == organization_id))}
  end

  def reachable(context), do: call(context)

  @doc "The session a write to `club` runs in: the scope of the gym that runs it."
  def write_context(club, %{user_id: user_id}),
    do: %{organization_id: club.organization_id, user_id: user_id}

  def find_channel(clubs, channel_id) do
    Enum.find_value(clubs, {:error, :not_found}, fn club ->
      case Enum.find(club.channels, &(&1.id == channel_id)) do
        nil -> nil
        channel -> {:ok, club, channel}
      end
    end)
  end

  # Open clubs the person joined, and those of gyms where they are staff.
  defp open_clubs(context, user_id, by_organization) do
    joined =
      context
      |> Community.open_club_memberships_of(user_id)
      |> Enum.filter(&(&1.status == "active"))
      |> MapSet.new(& &1.club_id)

    staff_of =
      for {organization_id, membership} <- by_organization,
          Community.club_role(membership.membership) == "staff",
          do: organization_id

    staffed =
      if staff_of == [],
        do: [],
        else: Community.list_open_clubs(context, %{organization_ids: staff_of, limit: 200})

    ids = Enum.uniq(MapSet.to_list(joined) ++ Enum.map(staffed, & &1.id))

    context
    |> Community.list_clubs_by_ids(ids)
    |> Enum.filter(&(&1.kind == "open"))
    |> Enum.flat_map(fn club ->
      gym_role =
        case by_organization[club.organization_id] do
          nil -> "member"
          membership -> Community.club_role(membership.membership)
        end

      status = if MapSet.member?(joined, club.id), do: "active"

      case Community.open_club_role(gym_role, status) do
        nil -> []
        role -> [Map.put(club, :role, role)]
      end
    end)
  end

  defp boxes([], _by_organization), do: %{}

  defp boxes(open_clubs, by_organization) do
    open_clubs
    |> Enum.map(& &1.organization_id)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(by_organization, &1))
    |> case do
      [] -> %{}
      ids -> ids |> Organizations.public_boxes() |> Map.new(&{&1.organization_id, &1})
    end
  end

  # A gym created before ADR-138 that the backfill has not reached yet gets
  # its club the first time a member looks.
  defp ensure_clubs(context, organization_ids) do
    existing =
      context
      |> Community.list_clubs(organization_ids)
      |> Enum.filter(&(&1.kind == "gym"))
      |> MapSet.new(& &1.organization_id)

    organization_ids
    |> Enum.reject(&MapSet.member?(existing, &1))
    |> Enum.reduce_while(:ok, fn organization_id, :ok ->
      case Community.provision_gym_club(%{
             organization_id: organization_id,
             user_id: context.user_id
           }) do
        {:ok, _club} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp gym_face(club, membership) do
    settings = (membership.settings && membership.settings.settings) || %{}

    %{
      name: brand_name(settings) || membership.organization.name || club.name,
      organization_slug: membership.organization.slug,
      organization_name: brand_name(settings) || membership.organization.name,
      logo_url: settings["brand_logo_url"],
      primary_color: settings["brand_primary_color"]
    }
  end

  defp open_face(club, by_organization, boxes) do
    gym =
      case {by_organization[club.organization_id], boxes[club.organization_id]} do
        {nil, nil} ->
          %{organization_slug: nil, organization_name: nil, logo_url: nil, primary_color: nil}

        {nil, box} ->
          %{
            organization_slug: box.slug,
            organization_name: box.name,
            logo_url: box.logo_url,
            primary_color: box.primary_color
          }

        {membership, _box} ->
          gym_face(club, membership)
      end

    gym
    |> Map.take([:organization_slug, :organization_name, :logo_url, :primary_color])
    |> Map.put(:name, club.name)
  end

  defp brand_name(settings) do
    case settings["brand_name"] do
      name when is_binary(name) and name != "" -> String.trim(name)
      _none -> nil
    end
  end

  # The active coaches of the person in each gym where they are in a squad
  # someone else coaches: membership follows coaching (ADR-168).
  defp squad_coaches(context, gym_clubs, channel_memberships) do
    for club <- gym_clubs,
        Enum.any?(club.channels, fn channel ->
          channel.kind == "pt_squad" and channel.created_by_id != context.user_id and
            Community.squad_member?(Map.get(channel_memberships, channel.id))
        end),
        into: %{} do
      coach_ids =
        club
        |> write_context(context)
        |> Coaching.list_relationships(%{client_user_id: context.user_id})
        |> Enum.map(& &1.coach_user_id)

      {club.organization_id, coach_ids}
    end
  end

  defp present(club, role, face, {user_id, channel_memberships, coaches}, levels) do
    coach_ids = Map.get(coaches, club.organization_id, [])

    channels =
      club.channels
      |> Enum.filter(fn channel ->
        channel.kind != "pt_squad" or
          Community.squad_visible?(
            channel,
            user_id,
            Map.get(channel_memberships, channel.id),
            coach_ids
          )
      end)
      |> Enum.map(&present_channel(&1, role, Map.get(channel_memberships, &1.id)))
      |> Enum.filter(&visible?(&1, role, user_id))

    Map.merge(face, %{
      id: club.id,
      organization_id: club.organization_id,
      kind: club.kind,
      description: club.description,
      join_policy: club.join_policy,
      role: role,
      notify_level: Map.get(levels, club.id, "all"),
      channels: channels
    })
  end

  defp visible?(%{kind: "member_group"} = channel, role, user_id) do
    case channel.status do
      "active" -> channel.participant or role == "staff"
      "pending" -> role == "staff" or channel.created_by_id == user_id
      _declined -> false
    end
  end

  defp visible?(%{kind: "pt_squad"}, _role, _user_id), do: true

  # Invite-only channels (e.g. a season, ADR-167) are for participants and staff.
  defp visible?(%{membership: "invite"} = channel, role, _user_id),
    do: channel.participant or role == "staff"

  defp visible?(_channel, _role, _user_id), do: true

  defp present_channel(channel, role, membership) do
    joined? = Community.group_member?(membership)
    source = membership && membership.source
    admin? = joined? and membership.role == "admin"
    channel = Map.put(channel, :admin, admin?)
    channel_role = Community.channel_role(role, channel)

    %{
      id: channel.id,
      club_id: channel.club_id,
      organization_id: channel.organization_id,
      kind: channel.kind,
      name: channel.name,
      description: Map.get(channel, :description),
      status: Map.get(channel, :status, "active"),
      join_policy: Map.get(channel, :join_policy),
      created_by_id: Map.get(channel, :created_by_id),
      write_policy: channel.write_policy,
      membership: channel.membership,
      archived_at: channel.archived_at,
      participant: joined?,
      admin: admin?,
      requested: source == "requested",
      suggested: not joined? and source == "suggested",
      joined: Community.channel_in_feed?(channel, joined?),
      can_post: Community.can_post?(channel, role, joined?),
      can_leave: Community.channel_self_service?(channel) or channel.kind == "member_group",
      can_moderate: Community.can_moderate?(channel_role),
      can_pin: Community.can_pin?(channel, channel_role)
    }
  end
end
