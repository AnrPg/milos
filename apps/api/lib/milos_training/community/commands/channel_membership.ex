defmodule MilosTraining.Community.Commands.ChannelMembership do
  @moduledoc "A member joins or leaves an opt-in channel of their gym's club (ADR-138)."

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.ChannelPolicy

  def join(%{organization_id: organization_id, user_id: user_id} = context, channel_id) do
    with {:ok, channel} <- fetch(context, channel_id, organization_id),
         :ok <- self_service(channel),
         :ok <- CommunityStore.join_channel(context, channel, user_id, "opt_in"),
         do: {:ok, channel}
  end

  def leave(%{organization_id: organization_id, user_id: user_id} = context, channel_id) do
    with {:ok, channel} <- fetch(context, channel_id, organization_id),
         :ok <- self_service(channel),
         :ok <- CommunityStore.leave_channel(context, channel, user_id),
         do: {:ok, channel}
  end

  defp fetch(context, channel_id, organization_id) do
    case CommunityStore.get_channel(context, channel_id) do
      %{organization_id: ^organization_id} = channel -> {:ok, channel}
      _missing -> {:error, :not_found}
    end
  end

  defp self_service(channel),
    do: if(ChannelPolicy.self_service?(channel), do: :ok, else: {:error, :channel_not_optional})
end
