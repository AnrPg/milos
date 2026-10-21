defmodule Palee.Community.Commands.ClassGroups do
  @moduledoc """
  Class-slot groups (ADR-138 D7). Every active recurring class of a gym has
  an opt-in channel in the gym's club; a class that stops running has its
  channel archived (history stays readable). Frequent bookers are offered
  the group, never joined to it: a suggestion is a row they can accept or
  dismiss, and a member's own choice is never overwritten.
  """

  alias Palee.Community.CommunityStore
  alias Palee.Community.Domain.ChannelPolicy

  @context_type "class_series"

  @doc "`series` are the gym's active class series, `counts` recent bookings per member."
  def sync(%{organization_id: _} = context, series, counts) do
    with {:ok, club} <- CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels()),
         {:ok, channels} <- ensure_channels(context, club, series) do
      :ok =
        CommunityStore.archive_context_channels(
          context,
          club.id,
          @context_type,
          Enum.map(series, & &1.id)
        )

      pairs =
        for {series_id, user_id} <- ChannelPolicy.class_group_candidates(counts),
            channel_id = Map.get(channels, series_id),
            channel_id != nil,
            do: {channel_id, user_id}

      :ok = CommunityStore.suggest_channel_members(context, pairs)
      {:ok, %{channels: map_size(channels), suggestions: length(pairs)}}
    end
  end

  defp ensure_channels(context, club, series) do
    Enum.reduce_while(series, {:ok, %{}}, fn one, {:ok, acc} ->
      case CommunityStore.ensure_context_channel(
             context,
             club,
             ChannelPolicy.class_slot_channel(one)
           ) do
        {:ok, channel} -> {:cont, {:ok, Map.put(acc, one.id, channel.id)}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Joins a member to one of their gym club's built-in channels, e.g. the
  #challenges channel when they enter a challenge (`source: "auto"`).
  """
  def join_builtin(%{organization_id: _, user_id: user_id} = context, kind, source) do
    with {:ok, club} <- CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels()) do
      case Enum.find(club.channels, &(&1.kind == kind)) do
        nil -> {:error, :not_found}
        channel -> CommunityStore.join_channel(context, channel, user_id, source)
      end
    end
  end
end
