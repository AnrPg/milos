defmodule MilosTraining.Community do
  @moduledoc """
  Community bounded context (ADR-138): clubs, channels, posts, kudos and
  comments. A gym's club is provisioned with the gym; its members are the
  gym's active members (Organizations owns that list), so this context only
  stores what a member chose (notification level, opt-in channels).
  """

  alias MilosTraining.Community.Commands.{
    Blocks,
    ChannelMembership,
    ClassGroups,
    Events,
    Follows,
    Groups,
    OpenClubs,
    Posts,
    Reports,
    ProfilePosts,
    ProvisionGymClub,
    SetNotifyLevel
  }

  alias MilosTraining.Community.Queries.Feed
  alias MilosTraining.Community.{ClubMembership, CommunityStore, EventStore, SocialStore}

  alias MilosTraining.Community.Domain.{
    AudiencePolicy,
    ChannelPolicy,
    ClubPolicy,
    EventPolicy,
    EventSeries,
    FeedCursor,
    FollowPolicy,
    GroupPolicy,
    PostMediaPolicy,
    ReportPolicy,
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

  # Open clubs (ADR-143).
  defdelegate create_open_club(context, role, attrs), to: OpenClubs, as: :create
  defdelegate update_open_club(context, club, role, attrs), to: OpenClubs, as: :update
  defdelegate archive_open_club(context, club, role, now), to: OpenClubs, as: :archive
  defdelegate join_open_club(context, club), to: OpenClubs, as: :join
  defdelegate leave_open_club(context, club), to: OpenClubs, as: :leave

  defdelegate answer_club_request(context, club, role, user_id, approve?),
    to: OpenClubs,
    as: :answer_request

  defdelegate remove_club_member(context, club, role, user_id), to: OpenClubs, as: :remove_member

  defdelegate set_open_club_notify_level(context, club, level),
    to: OpenClubs,
    as: :set_notify_level

  defdelegate club_memberships(context, club_id, status \\ nil), to: OpenClubs, as: :memberships
  defdelegate open_club_memberships_of(context, user_id), to: OpenClubs, as: :memberships_of
  defdelegate list_open_clubs(context, filter), to: OpenClubs, as: :list
  defdelegate open_club_member_counts(context, ids), to: OpenClubs, as: :member_counts
  defdelegate list_clubs_by_ids(context, ids), to: OpenClubs, as: :by_ids
  defdelegate open_club_role(gym_role, membership_status), to: ClubPolicy, as: :role
  def open_club_join_policies, do: ClubPolicy.join_policies()

  # Member groups (ADR-143).
  defdelegate community_settings(context), to: Groups, as: :settings
  defdelegate put_community_settings(context, attrs), to: Groups, as: :put_settings
  defdelegate propose_group(context, club, role, attrs), to: Groups, as: :propose
  defdelegate list_groups(context, club_id, filter \\ %{}), to: Groups, as: :list
  defdelegate group_members(context, group_id), to: Groups, as: :members
  defdelegate decide_group(context, group, role, decision, now), to: Groups, as: :decide
  defdelegate join_group(context, group, membership), to: Groups, as: :join
  defdelegate leave_group(context, group, membership, now), to: Groups, as: :leave

  defdelegate answer_group_request(context, group, actor, user_id, approve?),
    to: Groups,
    as: :answer_request

  defdelegate set_group_admin(context, group, actor, user_id, admin?), to: Groups, as: :set_admin
  defdelegate remove_group_member(context, group, actor, user_id), to: Groups, as: :remove_member
  defdelegate update_group(context, group, actor, attrs), to: Groups, as: :update
  defdelegate archive_group(context, group, actor, now), to: Groups, as: :archive
  defdelegate reopen_group(context, group, role, now), to: Groups, as: :reopen
  defdelegate quiet_groups(context, now), to: Groups
  defdelegate mark_group_warned(context, group, now), to: Groups, as: :mark_warned
  defdelegate group_member?(membership), to: Groups, as: :member?
  defdelegate channel_memberships_of(context, user_id, channel_ids), to: CommunityStore
  defdelegate group_quiet_step(group, now), to: GroupPolicy, as: :quiet_step
  defdelegate group_live?(group), to: GroupPolicy, as: :live?
  defdelegate can_manage_group?(membership_role, club_role), to: GroupPolicy, as: :can_manage?
  def group_lifecycle, do: GroupPolicy.lifecycle()
  def member_group_options, do: MilosTraining.Community.CommunitySettings.member_group_options()
  def group_join_policies, do: MilosTraining.Community.Channel.join_policies()

  # Reports (ADR-143).
  defdelegate report(context, target, attrs), to: Reports
  defdelegate list_reports(context, filter), to: Reports, as: :list
  defdelegate resolve_reports(context, target_type, target_id, action), to: Reports, as: :resolve
  defdelegate reported_ids(context, user_id, type), to: Reports
  defdelegate report_action_applies?(action, target_type), to: ReportPolicy, as: :action_applies?
  def report_reasons, do: ReportPolicy.reasons()
  def report_actions, do: ReportPolicy.actions()

  # Events (ADR-153).
  defdelegate create_event(context, club, attrs, opts), to: Events, as: :create
  defdelegate update_event(context, event, attrs, scope, opts), to: Events, as: :update
  defdelegate cancel_event(context, event, scope, reason, now), to: Events, as: :cancel
  defdelegate rsvp_event(context, event_id, user_id, facts, now), to: Events, as: :rsvp

  defdelegate withdraw_from_event(context, event_id, user_id, actor_id, now),
    to: Events,
    as: :withdraw

  defdelegate check_in_attendee(context, event, user_id, on?, now), to: Events, as: :check_in

  defdelegate record_event_payment(context, event_id, user_id, method, now, record),
    to: Events,
    as: :record_payment

  defdelegate claim_event_step(context, event_id, field, now), to: Events, as: :claim
  defdelegate mark_trial_offered(context, attendees, now), to: Events
  defdelegate get_event(context, id), to: EventStore
  defdelegate list_events(context, filter), to: EventStore
  defdelegate list_attendees(context, event_ids, statuses \\ nil), to: EventStore
  defdelegate get_attendee(context, event_id, user_id), to: EventStore
  defdelegate attendee_counts(context, event_ids), to: EventStore
  defdelegate count_guests(context, event_id, inviter_id), to: EventStore
  defdelegate attendances_of(context, user_id, statuses), to: EventStore
  defdelegate events_reminder_due(context, window), to: EventStore, as: :reminders_due

  defdelegate mark_event_conversions(context, user_id, window, at),
    to: EventStore,
    as: :mark_converted

  def link_event_post(context, event, post_id),
    do: EventStore.update_event(context, event, %{post_id: post_id})

  def event_capability, do: EventPolicy.capability()
  def event_editable_fields, do: MilosTraining.Community.Event.editable_fields()
  def event_scopes, do: EventPolicy.scopes()
  def event_reminder_minutes, do: EventPolicy.reminder_minutes()
  def event_conversion_days, do: EventPolicy.conversion_days()
  def event_series_max, do: EventSeries.max_occurrences()
  def attendee_statuses, do: MilosTraining.Community.EventAttendee.statuses()
  def attendee_sources, do: MilosTraining.Community.EventAttendee.sources()
  def event_payment_methods, do: MilosTraining.Community.EventAttendee.payment_methods()
  defdelegate event_spots_left(event, going), to: EventPolicy, as: :spots_left
  defdelegate event_show_names?(club_member?), to: EventPolicy, as: :show_names?
  defdelegate event_notable_changes(earlier, later), to: EventPolicy, as: :notable_changes
  defdelegate event_reminder_due?(event, now), to: EventPolicy, as: :reminder_due?
  defdelegate event_trial_offer_check(event, now), to: EventPolicy, as: :trial_offer_check

  defdelegate event_trial_offer_recipients(attendees, member_ids),
    to: EventPolicy,
    as: :trial_offer_recipients

  defdelegate event_stats(event, attendees, trial_requests, now), to: EventPolicy, as: :stats
  defdelegate event_open_for_rsvp(event, now), to: EventPolicy, as: :open_for_rsvp
  defdelegate event_guest_check(event, inviter_status, guests), to: EventPolicy, as: :guest_check

  defdelegate event_group_channel_check(channel, club_id),
    to: EventPolicy,
    as: :group_channel_check

  defdelegate event_group_admin?(channel, membership), to: EventPolicy, as: :group_admin?
  defdelegate event_manage_check(actor, channel_id), to: EventPolicy, as: :manage_check
  defdelegate event_belongs?(event, facts), to: EventPolicy, as: :belongs?
  defdelegate event_visible?(event, facts), to: EventPolicy, as: :visible?
  defdelegate event_can_rsvp?(event, belongs?, my_status, now), to: EventPolicy, as: :can_rsvp?
  def event_late_cancel_window_days, do: EventPolicy.late_cancel_window_days()

  @doc "Late cancels per person at the box since `since`: `%{user_id => count}`."
  defdelegate late_cancel_counts(context, user_ids, since), to: EventStore

  # Posts (M7).
  defdelegate create_post(context, channel, role, joined?, attrs), to: Posts, as: :create
  defdelegate fetch_post(context, post_id), to: Posts, as: :fetch
  defdelegate find_post(context, post_id), to: Posts, as: :find
  defdelegate get_comment(context, comment_id), to: CommunityStore
  defdelegate hide_comment(context, comment, role, hidden?, now), to: Posts
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
  def shareable_attachment_types, do: MilosTraining.Community.Post.shareable_attachment_types()

  defdelegate list_public_posts(context, organization_ids, viewer_id, page),
    to: CommunityStore

  # Photos and videos in posts (ADR-157).
  defdelegate validate_post_media(kinds), to: PostMediaPolicy, as: :compose
  defdelegate post_media_status(states), to: PostMediaPolicy, as: :status
  defdelegate post_media_visible?(post, viewer_id), to: PostMediaPolicy, as: :visible?
  def post_media_statuses, do: PostMediaPolicy.statuses()
  def max_post_images, do: PostMediaPolicy.max_images()

  @doc "Locked read-modify-write of a club (`community_post`) or profile post's media."
  def update_post_media(context, "community_post", id, fun),
    do: CommunityStore.update_post_media(context, id, fun)

  def update_post_media(context, "profile_post", id, fun),
    do: SocialStore.update_profile_post_media(context, id, fun)

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
  defdelegate hidden_member_ids(ids), to: SocialStore

  # Blocking a person (ADR-169 §5).
  defdelegate block_user(context, blocked_id), to: Blocks, as: :block
  defdelegate unblock_user(context, blocked_id), to: Blocks, as: :unblock
  defdelegate list_blocks(context), to: Blocks, as: :list
  defdelegate blocked_user_ids(context), to: Blocks, as: :blocked_ids

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
  defdelegate channel_role(club_role, channel), to: ChannelPolicy

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
