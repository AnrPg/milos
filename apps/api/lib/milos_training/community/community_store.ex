defmodule MilosTraining.Community.CommunityStore do
  @moduledoc """
  Facade over the configured Community adapter. Every call runs inside a
  `RepoContext` session: the gym's scope for writes, a member's personal
  session for the cross-gym reads (ADR-138).
  """

  @behaviour MilosTraining.Community.Ports.CommunityStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :community_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def ensure_gym_club(context, channels), do: tenant_call(context, :ensure_gym_club, [channels])
  @impl true
  def list_clubs(context, organization_ids),
    do: tenant_call(context, :list_clubs, [organization_ids])

  @impl true
  def get_club(context, id), do: tenant_call(context, :get_club, [id])
  @impl true
  def get_channel(context, id), do: tenant_call(context, :get_channel, [id])

  @impl true
  def joined_channel_ids(context, user_id, channel_ids),
    do: tenant_call(context, :joined_channel_ids, [user_id, channel_ids])

  @impl true
  def join_channel(context, channel, user_id, source),
    do: tenant_call(context, :join_channel, [channel, user_id, source])

  @impl true
  def leave_channel(context, channel, user_id),
    do: tenant_call(context, :leave_channel, [channel, user_id])

  @impl true
  def suggested_channel_ids(context, user_id, channel_ids),
    do: tenant_call(context, :suggested_channel_ids, [user_id, channel_ids])

  @impl true
  def ensure_context_channel(context, club, spec),
    do: tenant_call(context, :ensure_context_channel, [club, spec])

  @impl true
  def archive_context_channels(context, club_id, context_type, keep_context_ids),
    do: tenant_call(context, :archive_context_channels, [club_id, context_type, keep_context_ids])

  @impl true
  def suggest_channel_members(context, pairs),
    do: tenant_call(context, :suggest_channel_members, [pairs])

  @impl true
  def notify_levels(context, user_id, club_ids),
    do: tenant_call(context, :notify_levels, [user_id, club_ids])

  @impl true
  def put_notify_level(context, club, user_id, level),
    do: tenant_call(context, :put_notify_level, [club, user_id, level])

  # Open clubs.
  @impl true
  def create_club(context, attrs, channels),
    do: tenant_call(context, :create_club, [attrs, channels])

  @impl true
  def update_club(context, id, attrs), do: tenant_call(context, :update_club, [id, attrs])
  @impl true
  def list_clubs_by_ids(context, ids), do: tenant_call(context, :list_clubs_by_ids, [ids])
  @impl true
  def list_open_clubs(context, filter), do: tenant_call(context, :list_open_clubs, [filter])

  @impl true
  def open_club_member_counts(context, ids),
    do: tenant_call(context, :open_club_member_counts, [ids])

  @impl true
  def club_memberships_of(context, user_id),
    do: tenant_call(context, :club_memberships_of, [user_id])

  @impl true
  def list_club_memberships(context, club_id, status),
    do: tenant_call(context, :list_club_memberships, [club_id, status])

  @impl true
  def get_club_membership(context, club_id, user_id),
    do: tenant_call(context, :get_club_membership, [club_id, user_id])

  @impl true
  def put_club_membership(context, club, user_id, attrs),
    do: tenant_call(context, :put_club_membership, [club, user_id, attrs])

  @impl true
  def delete_club_membership(context, club_id, user_id),
    do: tenant_call(context, :delete_club_membership, [club_id, user_id])

  # Member groups.
  @impl true
  def get_community_settings(context), do: tenant_call(context, :get_community_settings, [])

  @impl true
  def put_community_settings(context, attrs),
    do: tenant_call(context, :put_community_settings, [attrs])

  @impl true
  def create_group(context, club, spec, creator_id, status),
    do: tenant_call(context, :create_group, [club, spec, creator_id, status])

  @impl true
  def list_groups(context, club_id, filter),
    do: tenant_call(context, :list_groups, [club_id, filter])

  @impl true
  def update_group(context, id, attrs), do: tenant_call(context, :update_group, [id, attrs])

  @impl true
  def update_group_lifecycle(context, id, attrs),
    do: tenant_call(context, :update_group_lifecycle, [id, attrs])

  @impl true
  def channel_memberships_of(context, user_id, channel_ids),
    do: tenant_call(context, :channel_memberships_of, [user_id, channel_ids])

  @impl true
  def list_channel_memberships(context, channel_id),
    do: tenant_call(context, :list_channel_memberships, [channel_id])

  @impl true
  def put_channel_membership(context, channel, user_id, attrs),
    do: tenant_call(context, :put_channel_membership, [channel, user_id, attrs])

  @impl true
  def quiet_groups(context, cutoff), do: tenant_call(context, :quiet_groups, [cutoff])

  # Reports.
  @impl true
  def create_report(context, attrs), do: tenant_call(context, :create_report, [attrs])
  @impl true
  def list_reports(context, filter), do: tenant_call(context, :list_reports, [filter])

  @impl true
  def resolve_reports(context, target_type, target_id, attrs),
    do: tenant_call(context, :resolve_reports, [target_type, target_id, attrs])

  @impl true
  def reported_ids(context, reporter_id, target_type),
    do: tenant_call(context, :reported_ids, [reporter_id, target_type])

  @impl true
  def hide_comment(context, id, attrs), do: tenant_call(context, :hide_comment, [id, attrs])

  @impl true
  def create_post(context, attrs), do: tenant_call(context, :create_post, [attrs])
  @impl true
  def get_post(context, id, viewer_id), do: tenant_call(context, :get_post, [id, viewer_id])
  @impl true
  def list_posts(context, filter), do: tenant_call(context, :list_posts, [filter])

  @impl true
  def list_pinned_posts(context, channel_ids, viewer_id),
    do: tenant_call(context, :list_pinned_posts, [channel_ids, viewer_id])

  @impl true
  def list_public_posts(context, organization_ids, viewer_id, page),
    do: tenant_call(context, :list_public_posts, [organization_ids, viewer_id, page])

  @impl true
  def moderate_post(context, id, attrs), do: tenant_call(context, :moderate_post, [id, attrs])
  @impl true
  def react(context, post, user_id, kind), do: tenant_call(context, :react, [post, user_id, kind])

  @impl true
  def unreact(context, post, user_id, kind),
    do: tenant_call(context, :unreact, [post, user_id, kind])

  @impl true
  def list_comments(context, post_id), do: tenant_call(context, :list_comments, [post_id])
  @impl true
  def get_comment(context, id), do: tenant_call(context, :get_comment, [id])
  @impl true
  def add_comment(context, attrs), do: tenant_call(context, :add_comment, [attrs])
  @impl true
  def delete_comment(context, id, now), do: tenant_call(context, :delete_comment, [id, now])
end
