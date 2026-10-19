defmodule MilosTraining.Community do
  @moduledoc """
  Community bounded context (ADR-138): clubs, channels, posts, kudos and
  comments. A gym's club is provisioned with the gym; its members are the
  gym's active members (Organizations owns that list), so this context only
  stores what a member chose (notification level, opt-in channels).
  """

  alias MilosTraining.Community.Commands.{
    ChannelMembership,
    ClassGroups,
    Follows,
    Posts,
    ProfilePosts,
    ProvisionGymClub,
    SetNotifyLevel
  }

  alias MilosTraining.Community.Queries.Feed
  alias MilosTraining.Community.{ClubMembership, CommunityStore, SocialStore}

  alias MilosTraining.Community.Domain.{
    AudiencePolicy,
    ChannelPolicy,
    FeedCursor,
    FollowPolicy,
    TenantDataPolicy
  }

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
  defdelegate suggested_channel_ids(context, user_id, channel_ids), to: CommunityStore
  defdelegate sync_class_groups(context, series, counts), to: ClassGroups, as: :sync
  defdelegate join_builtin_channel(context, kind, source), to: ClassGroups, as: :join_builtin
  def class_group_suggestion, do: ChannelPolicy.class_group_suggestion()
  def notify_level_options, do: ClubMembership.notify_levels()

  # Posts (M7).
  defdelegate create_post(context, channel, role, joined?, attrs), to: Posts, as: :create
  defdelegate fetch_post(context, post_id), to: Posts, as: :fetch
  defdelegate delete_post(context, post, role, now), to: Posts, as: :delete
  defdelegate hide_post(context, post, role, hidden?, now), to: Posts, as: :hide
  defdelegate pin_post(context, post, channel, role, pinned?, now), to: Posts, as: :pin
  defdelegate set_kudos(context, post, on?), to: Posts, as: :kudos
  defdelegate add_comment(context, post, body), to: Posts, as: :comment
  defdelegate delete_comment(context, comment_id, role, now), to: Posts
  defdelegate list_comments(context, post_id), to: CommunityStore
  defdelegate feed_page(context, params), to: Feed, as: :page
  defdelegate pinned_posts(context, channel_ids, viewer_id), to: Feed, as: :pinned
  def attachment_types, do: MilosTraining.Community.Post.attachment_types()

  defdelegate list_public_posts(context, organization_ids, viewer_id, page),
    to: CommunityStore

  # Follows (ADR-142).
  defdelegate follow(context, type, target_id, target), to: Follows
  defdelegate unfollow(context, type, target_id), to: Follows
  defdelegate follow_status(context, type, target_id), to: Follows, as: :status
  defdelegate accept_follow(context, follow_id, now), to: Follows, as: :accept
  defdelegate remove_incoming_follow(context, follow_id), to: Follows, as: :remove_incoming

  defdelegate list_incoming_follows(context, type, target_id, status, page),
    to: SocialStore,
    as: :list_incoming

  defdelegate list_outgoing_follows(context, follower_id, types, statuses, page),
    to: SocialStore,
    as: :list_outgoing

  defdelegate count_incoming_follows(context, type, target_id, status),
    to: SocialStore,
    as: :count_incoming

  defdelegate count_outgoing_follows(context, follower_id, types, statuses),
    to: SocialStore,
    as: :count_outgoing

  defdelegate followed_ids(context, follower_id, type), to: SocialStore, as: :active_target_ids
  defdelegate follow_statuses(context, follower_id, type, ids), to: SocialStore
  defdelegate get_follow(context, follower_id, type, target_id), to: SocialStore
  defdelegate follower_counts(type, ids), to: SocialStore
  defdelegate following_count(user_id), to: SocialStore
  def follow_target_types, do: FollowPolicy.target_types()

  # Social settings (ADR-142 decision 12).
  defdelegate social_settings(context, user_id), to: SocialStore, as: :get_social_settings
  defdelegate put_social_settings(context, user_id, attrs), to: SocialStore
  defdelegate booking_sharer_ids(context), to: SocialStore

  # Profile posts (ADR-142).
  defdelegate create_profile_post(context, audience, attrs), to: ProfilePosts, as: :create
  defdelegate fetch_profile_post(context, post_id), to: ProfilePosts, as: :fetch
  defdelegate delete_profile_post(context, post, now), to: ProfilePosts, as: :delete
  defdelegate set_profile_kudos(context, post, on?), to: ProfilePosts, as: :kudos
  defdelegate add_profile_comment(context, post, body), to: ProfilePosts, as: :comment

  defdelegate delete_profile_comment(context, comment_id, now),
    to: ProfilePosts,
    as: :delete_comment

  defdelegate list_profile_comments(context, post_id), to: SocialStore
  defdelegate list_profile_posts(context, filter), to: SocialStore
  defdelegate count_profile_posts(context, author_id), to: SocialStore

  # Audiences (ADR-142).
  def audiences, do: AudiencePolicy.audiences()
  defdelegate post_scope(params), to: AudiencePolicy, as: :scope
  defdelegate club_audience_allowed?(audience, role), to: AudiencePolicy

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
