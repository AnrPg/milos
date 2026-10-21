defmodule MilosTraining.Community.Commands.SeasonChannels do
  @moduledoc """
  A season's crew channel (ADR-167): one invite-only `season` channel in the
  gym's club per season. Confirmed participants are added (`source: "auto"`),
  a member who leaves the season is removed, and the channel is archived once
  the season is over (history stays readable to those who were in it).
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.ChannelPolicy

  @context_type "season_offering"

  @doc "The season's channel, created on first use; `offering` has `id` and `title`."
  def ensure(%{organization_id: _} = context, offering) do
    with {:ok, club} <- CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels()) do
      CommunityStore.ensure_context_channel(context, club, ChannelPolicy.season_channel(offering))
    end
  end

  def add(context, channel, user_id),
    do: CommunityStore.join_channel(context, channel, user_id, "auto")

  def remove(context, channel, user_id),
    do: CommunityStore.leave_channel(context, channel, user_id)

  @doc "Archives every season channel of the gym except those of `live_offering_ids`."
  def archive_ended(%{organization_id: _} = context, live_offering_ids) do
    with {:ok, club} <- CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels()) do
      CommunityStore.archive_context_channels(context, club.id, @context_type, live_offering_ids)
    end
  end
end
