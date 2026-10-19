defmodule MilosTraining.Community.SocialStore do
  @moduledoc """
  Facade over the follows and profile posts adapter (ADR-142). Every call
  runs inside the caller's `RepoContext` session, normally the acting
  member's personal session; follower counts others may see come from a
  narrow SQL function and need no session.
  """

  @behaviour MilosTraining.Community.Ports.SocialStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :community_social_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get_follow(context, follower_id, type, target_id),
    do: call(context, :get_follow, [follower_id, type, target_id])

  @impl true
  def get_follow_by_id(context, id),
    do: call(context, :get_follow_by_id, [id])

  @impl true
  def insert_follow(context, attrs),
    do: call(context, :insert_follow, [attrs])

  @impl true
  def delete_follow(context, follower_id, type, target_id),
    do: call(context, :delete_follow, [follower_id, type, target_id])

  @impl true
  def accept_follow(context, id, now),
    do: call(context, :accept_follow, [id, now])

  @impl true
  def delete_follow_by_id(context, id),
    do: call(context, :delete_follow_by_id, [id])

  @impl true
  def list_incoming(context, type, target_id, status, page),
    do: call(context, :list_incoming, [type, target_id, status, page])

  @impl true
  def list_outgoing(context, follower_id, types, statuses, page),
    do: call(context, :list_outgoing, [follower_id, types, statuses, page])

  @impl true
  def count_incoming(context, type, target_id, status),
    do: call(context, :count_incoming, [type, target_id, status])

  @impl true
  def count_outgoing(context, follower_id, types, statuses),
    do: call(context, :count_outgoing, [follower_id, types, statuses])

  @impl true
  def active_target_ids(context, follower_id, type),
    do: call(context, :active_target_ids, [follower_id, type])

  @impl true
  def follow_statuses(context, follower_id, type, ids),
    do: call(context, :follow_statuses, [follower_id, type, ids])

  @impl true
  def create_profile_post(context, attrs),
    do: call(context, :create_profile_post, [attrs])

  @impl true
  def get_profile_post(context, id, viewer_id),
    do: call(context, :get_profile_post, [id, viewer_id])

  @impl true
  def list_profile_posts(context, filter),
    do: call(context, :list_profile_posts, [filter])

  @impl true
  def count_profile_posts(context, author_id),
    do: call(context, :count_profile_posts, [author_id])

  @impl true
  def delete_profile_post(context, id, now),
    do: call(context, :delete_profile_post, [id, now])

  @impl true
  def react_profile_post(context, post_id, user_id, kind),
    do: call(context, :react_profile_post, [post_id, user_id, kind])

  @impl true
  def unreact_profile_post(context, post_id, user_id, kind),
    do: call(context, :unreact_profile_post, [post_id, user_id, kind])

  @impl true
  def list_profile_comments(context, post_id),
    do: call(context, :list_profile_comments, [post_id])

  @impl true
  def get_profile_comment(context, id),
    do: call(context, :get_profile_comment, [id])

  @impl true
  def add_profile_comment(context, attrs),
    do: call(context, :add_profile_comment, [attrs])

  @impl true
  def delete_profile_comment(context, id, now),
    do: call(context, :delete_profile_comment, [id, now])

  @impl true
  def follower_counts(type, ids), do: adapter().follower_counts(type, ids)

  @impl true
  def following_count(user_id), do: adapter().following_count(user_id)
end
