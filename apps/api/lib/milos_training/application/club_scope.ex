defmodule MilosTraining.Application.ClubScope do
  @moduledoc """
  The member's clubs as they apply to them (ADR-138): every club of every gym
  they actively belong to, their role in it (derived from their gym roles),
  and each channel's governance for them. Shared by the club bar, the feed
  and the realtime join.
  """

  alias MilosTraining.{Community, Organizations}

  def call(%{user_id: user_id} = context) do
    memberships = Organizations.list_memberships(user_id)
    by_organization = Map.new(memberships, &{&1.organization.id, &1})
    organization_ids = Map.keys(by_organization)

    with :ok <- ensure_clubs(context, organization_ids) do
      clubs = Community.list_clubs(context, organization_ids)
      channel_ids = Enum.flat_map(clubs, fn club -> Enum.map(club.channels, & &1.id) end)
      joined = MapSet.new(Community.joined_channel_ids(context, user_id, channel_ids))
      suggested = MapSet.new(Community.suggested_channel_ids(context, user_id, channel_ids))
      levels = Community.notify_levels(context, user_id, Enum.map(clubs, & &1.id))

      {:ok,
       clubs
       |> Enum.map(&present(&1, by_organization[&1.organization_id], {joined, suggested}, levels))
       |> Enum.sort_by(&{&1.kind != "gym", String.downcase(&1.name)})}
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

  def find_channel(clubs, channel_id) do
    Enum.find_value(clubs, {:error, :not_found}, fn club ->
      case Enum.find(club.channels, &(&1.id == channel_id)) do
        nil -> nil
        channel -> {:ok, club, channel}
      end
    end)
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

  defp present(club, membership, membership_sets, levels) do
    role = Community.club_role(membership.membership)
    settings = (membership.settings && membership.settings.settings) || %{}

    %{
      id: club.id,
      organization_id: club.organization_id,
      organization_slug: membership.organization.slug,
      kind: club.kind,
      name: club_name(club, membership.organization, settings),
      logo_url: settings["brand_logo_url"],
      primary_color: settings["brand_primary_color"],
      role: role,
      notify_level: Map.get(levels, club.id, "all"),
      channels: Enum.map(club.channels, &present_channel(&1, role, membership_sets))
    }
  end

  defp club_name(%{kind: "gym"}, organization, settings) do
    case settings["brand_name"] do
      name when is_binary(name) and name != "" -> String.trim(name)
      _none -> organization.name
    end
  end

  defp club_name(club, _organization, _settings), do: club.name

  defp present_channel(channel, role, {joined, suggested}) do
    joined? = MapSet.member?(joined, channel.id)

    %{
      id: channel.id,
      club_id: channel.club_id,
      organization_id: channel.organization_id,
      kind: channel.kind,
      name: channel.name,
      write_policy: channel.write_policy,
      membership: channel.membership,
      archived_at: channel.archived_at,
      participant: joined?,
      suggested: not joined? and MapSet.member?(suggested, channel.id),
      joined: Community.channel_in_feed?(channel, joined?),
      can_post: Community.can_post?(channel, role, joined?),
      can_leave: Community.channel_self_service?(channel)
    }
  end
end
