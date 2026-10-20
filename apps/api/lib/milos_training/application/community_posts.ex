defmodule MilosTraining.Application.CommunityPosts do
  @moduledoc """
  Posting in a club (ADR-138, M7; ADR-143): compose with an optional journal
  attachment, moderation (D8), kudos and comments. Staff may make a post
  public (ADR-142): it then also shows on the box page and to its followers.

  The club is the one the channel or post belongs to, among those the request
  reaches (`ClubScope.reachable/1`): a gym route reaches its gym's clubs, a
  personal route also the open clubs the member joined elsewhere. Writes run
  in the scope of the gym that runs the club; a member group's admins
  moderate inside their group. Every change is announced on the club's
  realtime topic.

  ADR-157: a post may carry up to ten photos or one video (`media_ids`,
  the author's uploads, in order), still processing when it is published.
  Deleting a post deletes its uploads.
  """

  alias MilosTraining.Application.{
    ClubScope,
    PostAttachment,
    PostMedia,
    PostPresenter,
    RealtimePublisher
  }

  alias MilosTraining.Community

  def create(%{user_id: user_id} = context, params) do
    audience = param(params, :audience)

    with {:ok, clubs} <- ClubScope.reachable(context),
         {:ok, club, channel} <- ClubScope.find_channel(clubs, param(params, :channel_id)),
         {:ok, attachment} <- attachment(user_id, params),
         {:ok, media} <- PostMedia.prepare(context, param(params, :media_ids)),
         attrs =
           attachment
           |> Map.merge(PostMedia.initial(media))
           |> Map.merge(%{
             body: param(params, :body),
             audience: audience,
             client_operation_id: param(params, :client_operation_id)
           }),
         write = ClubScope.write_context(club, context),
         {:ok, post} <-
           Community.create_post(write, channel, club.role, channel.participant, attrs),
         :ok <- attach_media(media, context, write, club, channel, post) do
      _ = PostAttachment.mark_posted(user_id, post)
      announce(club, "post_created", post)
      reload(context, club, post.id)
    end
  end

  # The uploads join the post; if another post took one meanwhile, this
  # post goes again.
  defp attach_media(media, context, write, club, channel, post) do
    case PostMedia.attach(media, context, PostMedia.ref("community_post", post)) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = Community.delete_post(write, post, role(club, channel), DateTime.utc_now())
        {:error, reason}
    end
  end

  def delete(context, post_id, now \\ DateTime.utc_now()) do
    with {:ok, club, channel, post} <- load(context, post_id),
         {:ok, _deleted} <-
           Community.delete_post(write(club, context), post, role(club, channel), now) do
      PostAttachment.restore(post.author_id, post)
      :ok = PostMedia.release(post)
      announce(club, "post_deleted", post)
      :ok
    end
  end

  def hide(context, post_id, hidden?, now \\ DateTime.utc_now()) do
    with {:ok, club, channel, post} <- load(context, post_id),
         {:ok, _post} <-
           Community.hide_post(write(club, context), post, role(club, channel), hidden?, now) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def pin(context, post_id, pinned?, now \\ DateTime.utc_now()) do
    with {:ok, club, channel, post} <- load(context, post_id),
         {:ok, _post} <-
           Community.pin_post(
             write(club, context),
             post,
             channel,
             role(club, channel),
             pinned?,
             now
           ) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def kudos(context, post_id, on?) do
    with {:ok, club, _channel, post} <- load(context, post_id),
         :ok <- Community.set_kudos(write(club, context), post, on?) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def comments(%{user_id: user_id} = context, post_id) do
    with {:ok, club, channel, post} <- load(context, post_id) do
      hidden_for_me = MapSet.new(Community.reported_ids(context, user_id, "comment"))
      moderator? = Community.can_moderate?(role(club, channel))

      shown =
        context
        |> Community.list_comments(post.id)
        |> Enum.reject(&MapSet.member?(hidden_for_me, &1.id))
        |> Enum.filter(&(is_nil(&1.hidden_at) or moderator? or &1.author_id == user_id))

      {:ok, PostPresenter.comments(shown, club, user_id, moderator?)}
    end
  end

  def comment(%{user_id: user_id} = context, post_id, body) do
    with {:ok, club, channel, post} <- load(context, post_id),
         :ok <- can_comment(channel),
         {:ok, comment} <- Community.add_comment(write(club, context), post, body) do
      announce(club, "post_updated", post)
      moderator? = Community.can_moderate?(role(club, channel))
      [presented] = PostPresenter.comments([comment], club, user_id, moderator?)
      {:ok, presented}
    end
  end

  def delete_comment(context, comment_id, now \\ DateTime.utc_now()) do
    with {:ok, club, channel, post, comment} <- load_comment(context, comment_id),
         :ok <-
           Community.delete_comment(write(club, context), comment.id, role(club, channel), now) do
      announce(club, "post_updated", post)
      :ok
    end
  end

  def hide_comment(context, comment_id, hidden?, now \\ DateTime.utc_now()) do
    with {:ok, club, channel, post, comment} <- load_comment(context, comment_id),
         :ok <-
           Community.hide_comment(
             write(club, context),
             comment,
             role(club, channel),
             hidden?,
             now
           ) do
      announce(club, "post_updated", post)
      :ok
    end
  end

  @doc "A post in the request's reach, with its club and channel as they apply to the member."
  def load(context, post_id) do
    with {:ok, clubs} <- ClubScope.reachable(context),
         {:ok, post} <- Community.find_post(context, post_id),
         {:ok, club, channel} <- ClubScope.find_channel(clubs, post.channel_id),
         true <- visible?(post, club, channel, context.user_id) || {:error, :not_found} do
      {:ok, club, channel, post}
    end
  end

  @doc "A comment in the request's reach, with its post, club and channel."
  def load_comment(context, comment_id) do
    with %{} = comment <- Community.get_comment(context, comment_id) || {:error, :not_found},
         {:ok, club, channel, post} <- load(context, comment.post_id) do
      {:ok, club, channel, post, comment}
    end
  end

  # Whoever cannot write in a proposed or archived group cannot comment there either.
  defp can_comment(%{kind: "member_group", can_post: false}),
    do: {:error, :cannot_post_in_channel}

  defp can_comment(_channel), do: :ok

  # Hidden posts, and posts whose media are not ready (ADR-157), show to
  # their author and to those who moderate the channel.
  defp visible?(post, club, channel, user_id) do
    (is_nil(post.hidden_at) and Community.post_media_visible?(post, user_id)) or
      post.author_id == user_id or Community.can_moderate?(role(club, channel))
  end

  defp role(club, channel), do: Community.channel_role(club.role, channel)
  defp write(club, context), do: ClubScope.write_context(club, context)

  defp reload(context, club, post_id) do
    with {:ok, post} <- Community.find_post(context, post_id) do
      [presented] = PostPresenter.posts([post], [club], context.user_id)
      {:ok, presented}
    end
  end

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

  defp announce(club, event, post) do
    RealtimePublisher.broadcast("community:club:#{club.id}", event, %{
      post_id: post.id,
      channel_id: post.channel_id
    })
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
