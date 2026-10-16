defmodule MilosTraining.Application.CommunityPreferences do
  @moduledoc "A member's choices about their gym's club (ADR-138): notification level and opt-in channels."

  alias MilosTraining.Community

  def set_notify_level(context, club_id, level),
    do: Community.set_notify_level(context, club_id, level)

  def join_channel(context, channel_id) do
    with {:ok, channel} <- Community.join_channel(context, channel_id),
         do: {:ok, %{channel_id: channel.id, joined: true}}
  end

  def leave_channel(context, channel_id) do
    with {:ok, channel} <- Community.leave_channel(context, channel_id),
         do: {:ok, %{channel_id: channel.id, joined: false}}
  end
end
