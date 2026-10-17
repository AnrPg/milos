defmodule MilosTraining.Community.Commands.ProvisionGymClub do
  @moduledoc """
  Makes sure a gym has its club and the club's built-in channels (ADR-138).
  Idempotent: runs inside organization provisioning, from the backfill job
  and before reads that need the club, and never duplicates anything.
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.ChannelPolicy

  def call(%{organization_id: organization_id} = context) when is_binary(organization_id),
    do: CommunityStore.ensure_gym_club(context, ChannelPolicy.gym_channels())
end
