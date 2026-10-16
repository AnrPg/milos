defmodule MilosTraining.Community do
  @moduledoc """
  Community bounded context (ADR-138): clubs, channels, posts, kudos and
  comments. A gym's club is provisioned with the gym; its members are the
  gym's active members (Organizations owns that list), so this context only
  stores what a member chose (notification level, opt-in channels).
  """

  alias MilosTraining.Community.Commands.{ChannelMembership, ProvisionGymClub, SetNotifyLevel}
  alias MilosTraining.Community.{ClubMembership, CommunityStore}
  alias MilosTraining.Community.Domain.{ChannelPolicy, FeedCursor, TenantDataPolicy}

  def with_context(context, fun) when is_function(fun, 0),
    do: CommunityStore.with_context(context, fun)

  # Clubs and channels.
  defdelegate provision_gym_club(context), to: ProvisionGymClub, as: :call
  defdelegate list_clubs(context, organization_ids), to: CommunityStore
  defdelegate get_club(context, id), to: CommunityStore
  defdelegate get_channel(context, id), to: CommunityStore
  defdelegate joined_channel_ids(context, user_id, channel_ids), to: CommunityStore
  defdelegate notify_levels(context, user_id, club_ids), to: CommunityStore
  defdelegate join_channel(context, channel_id), to: ChannelMembership, as: :join
  defdelegate leave_channel(context, channel_id), to: ChannelMembership, as: :leave
  defdelegate set_notify_level(context, club_id, level), to: SetNotifyLevel, as: :call
  def notify_level_options, do: ClubMembership.notify_levels()

  # Governance rules (vision §7.1).
  defdelegate club_role(context_or_roles), to: ChannelPolicy
  defdelegate channel_in_feed?(channel, joined?), to: ChannelPolicy, as: :in_feed?
  defdelegate channel_self_service?(channel), to: ChannelPolicy, as: :self_service?
  defdelegate can_post?(channel, role, joined?), to: ChannelPolicy
  defdelegate can_pin?(channel, role), to: ChannelPolicy
  defdelegate can_delete_post?(post, user_id, role), to: ChannelPolicy
  defdelegate can_moderate?(role), to: ChannelPolicy

  # Feed paging.
  defdelegate encode_feed_cursor(post), to: FeedCursor, as: :encode
  defdelegate decode_feed_cursor(cursor), to: FeedCursor, as: :decode
  defdelegate sort_posts(posts), to: FeedCursor, as: :sort

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
