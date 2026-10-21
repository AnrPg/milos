defmodule Palee.Application.ProfilePosts do
  @moduledoc """
  ADR-142 (P2-M2): posts to the author's followers or to everyone, with an
  optional journal attachment, kudos and comments. They belong to the
  author, so they run in the member's personal session; RLS lets active
  followers read followers posts and anyone read public ones.

  ADR-157: up to ten photos or one video (`media_ids`). Deleting a post
  deletes its uploads.
  """

  alias Palee.Application.{PostAttachment, PostMedia, PostPresenter, RealtimePublisher}
  alias Palee.Community

  def create(%{user_id: user_id} = context, params) do
    audience = param(params, :audience)

    with {:ok, attachment} <- attachment(user_id, params),
         {:ok, media} <- PostMedia.prepare(context, param(params, :media_ids)),
         attrs =
           attachment
           |> Map.merge(PostMedia.initial(media))
           |> Map.merge(%{
             body: param(params, :body),
             client_operation_id: param(params, :client_operation_id)
           }),
         {:ok, post} <- Community.create_profile_post(context, audience, attrs),
         :ok <- attach_media(media, context, post),
         {:ok, post} <- Community.fetch_profile_post(context, post.id) do
      _ = PostAttachment.mark_posted(user_id, post)
      announce(post, "post_created")
      {:ok, present(post, user_id)}
    end
  end

  defp attach_media(media, context, post) do
    case PostMedia.attach(media, context, PostMedia.ref("profile_post", post)) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = Community.delete_profile_post(context, post, DateTime.utc_now())
        {:error, reason}
    end
  end

  def delete(%{user_id: user_id} = context, post_id, now \\ DateTime.utc_now()) do
    with {:ok, post} <- Community.fetch_profile_post(context, post_id),
         :ok <- Community.delete_profile_post(context, post, now) do
      PostAttachment.restore(user_id, post)
      :ok = PostMedia.release(post)
      announce(post, "post_deleted")
      :ok
    end
  end

  def kudos(%{user_id: user_id} = context, post_id, on?) do
    with {:ok, post} <- Community.fetch_profile_post(context, post_id),
         :ok <- Community.set_profile_kudos(context, post, on?),
         {:ok, post} <- Community.fetch_profile_post(context, post.id) do
      announce(post, "post_updated")
      {:ok, present(post, user_id)}
    end
  end

  def comments(%{user_id: user_id} = context, post_id) do
    with {:ok, post} <- Community.fetch_profile_post(context, post_id) do
      {:ok,
       context
       |> Community.list_profile_comments(post.id)
       |> PostPresenter.profile_comments(post, user_id)}
    end
  end

  def comment(%{user_id: user_id} = context, post_id, body) do
    with {:ok, post} <- Community.fetch_profile_post(context, post_id),
         {:ok, comment} <- Community.add_profile_comment(context, post, body) do
      announce(post, "post_updated")
      [presented] = PostPresenter.profile_comments([comment], post, user_id)
      {:ok, presented}
    end
  end

  def delete_comment(context, comment_id, now \\ DateTime.utc_now()),
    do: Community.delete_profile_comment(context, comment_id, now)

  defp present(post, viewer_id), do: hd(PostPresenter.profile_posts([post], viewer_id))

  defp attachment(user_id, params) do
    case {param(params, :attachment_type), param(params, :attachment_id)} do
      {nil, nil} ->
        {:ok, %{}}

      {type, id} when is_binary(type) and is_binary(id) ->
        PostAttachment.snapshot(user_id, type, id)

      _half ->
        {:error, :attachment_not_shareable}
    end
  end

  # Followers' feeds refresh from the author's topic.
  defp announce(post, event) do
    RealtimePublisher.broadcast("community:profile:#{post.author_id}", event, %{post_id: post.id})
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
