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
  def notify_levels(context, user_id, club_ids),
    do: tenant_call(context, :notify_levels, [user_id, club_ids])

  @impl true
  def put_notify_level(context, club, user_id, level),
    do: tenant_call(context, :put_notify_level, [club, user_id, level])

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
