defmodule Palee.Community.Commands.ProvisionGymClub do
  @moduledoc """
  Makes sure a gym has its club and the club's built-in channels (ADR-138).
  Idempotent: runs inside organization provisioning, from the backfill job
  and before reads that need the club, and never duplicates anything.
  """

  alias Palee.Community.CommunityStore
  alias Palee.Community.Domain.ChannelPolicy

  def call(%{organization_id: organization_id} = context) when is_binary(organization_id),
    do: CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels())

  @doc """
  ADR-170: names the gym's club (an independent coach's «Team Νίκος»), only
  while it has no name of its own, then returns the club.
  """
  def call(%{organization_id: organization_id} = context, name)
      when is_binary(organization_id) and is_binary(name) do
    with {:ok, _club} <- call(context),
         :ok <- CommunityStore.name_gym_club(context, String.slice(String.trim(name), 0, 80)) do
      call(context)
    end
  end
end
