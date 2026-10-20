defmodule MilosTraining.Community.Domain.AudiencePolicy do
  @moduledoc """
  Who a post reaches (ADR-142, vision §6.2): a club channel, the author's
  followers, or everyone. Followers and public posts by a person are their
  own (profile posts). A club post is public only when staff make it so,
  speaking for the box; it then shows on the box page and to the box's
  followers as well as in its channel.
  """

  @club_audiences ~w(club_channel public)
  @profile_audiences ~w(followers public)

  def audiences, do: ~w(club_channel followers public)
  def profile_audiences, do: @profile_audiences

  @doc "Where a post with `audience` is stored: in a club, or on the author's profile."
  def scope(%{channel_id: channel_id}) when is_binary(channel_id), do: :club
  def scope(%{"channel_id" => channel_id}) when is_binary(channel_id), do: :club
  def scope(_params), do: :profile

  @doc "Whether someone with club `role` may post to a club channel with `audience`."
  def club_audience_allowed?("club_channel", _role), do: true
  def club_audience_allowed?("public", role), do: role == "staff"
  def club_audience_allowed?(_audience, _role), do: false

  def club_audience?(audience), do: audience in @club_audiences
  def profile_audience?(audience), do: audience in @profile_audiences
end
