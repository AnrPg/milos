defmodule MilosTraining.Application.CommunityPosts do
  @moduledoc """
  Posting in a gym's club (ADR-138, M7): compose with an optional journal
  attachment, moderation (D8), kudos and comments. Staff may make a post
  public (ADR-142): it then also shows on the box page and to its followers. Runs in the gym's scope;
  every change is announced on the club's realtime topic.
  """

  alias MilosTraining.Application.{ClubScope, PostAttachment, PostPresenter, RealtimePublisher}
  alias MilosTraining.Community

  def create(%{user_id: user_id} = context, params) do
    with {:ok, club} <- ClubScope.gym_club(context),
         {:ok, channel} <- channel(club, param(params, :channel_id)),
         {:ok, attachment} <- attachment(user_id, params),
         attrs =
           Map.merge(attachment, %{
             body: param(params, :body),
             audience: param(params, :audience),
             client_operation_id: param(params, :client_operation_id)
           }),
         {:ok, post} <-
           Community.create_post(context, channel, club.role, channel.participant, attrs) do
      _ = PostAttachment.mark_posted(user_id, post)
      [presented] = PostPresenter.posts([post], [club], user_id)
      announce(club, "post_created", post)
      {:ok, presented}
    end
  end

  def delete(context, post_id, now \\ DateTime.utc_now()) do
    with {:ok, club, post} <- load(context, post_id),
         {:ok, _deleted} <- Community.delete_post(context, post, club.role, now) do
      PostAttachment.restore(post.author_id, post)
      announce(club, "post_deleted", post)
      :ok
    end
  end

  def hide(context, post_id, hidden?, now \\ DateTime.utc_now()) do
    with {:ok, club, post} <- load(context, post_id),
         {:ok, _post} <- Community.hide_post(context, post, club.role, hidden?, now) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def pin(context, post_id, pinned?, now \\ DateTime.utc_now()) do
    with {:ok, club, post} <- load(context, post_id),
         {:ok, channel} <- channel(club, post.channel_id),
         {:ok, _post} <- Community.pin_post(context, post, channel, club.role, pinned?, now) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def kudos(context, post_id, on?) do
    with {:ok, club, post} <- load(context, post_id),
         :ok <- Community.set_kudos(context, post, on?) do
      announce(club, "post_updated", post)
      reload(context, club, post.id)
    end
  end

  def comments(%{user_id: user_id} = context, post_id) do
    with {:ok, club, post} <- load(context, post_id) do
      {:ok, PostPresenter.comments(Community.list_comments(context, post.id), club, user_id)}
    end
  end

  def comment(%{user_id: user_id} = context, post_id, body) do
    with {:ok, club, post} <- load(context, post_id),
         {:ok, comment} <- Community.add_comment(context, post, body) do
      announce(club, "post_updated", post)
      [presented] = PostPresenter.comments([comment], club, user_id)
      {:ok, presented}
    end
  end

  def delete_comment(context, comment_id, now \\ DateTime.utc_now()) do
    with {:ok, club} <- ClubScope.gym_club(context),
         :ok <- Community.delete_comment(context, comment_id, club.role, now),
         do: :ok
  end

  defp load(context, post_id) do
    with {:ok, club} <- ClubScope.gym_club(context),
         {:ok, post} <- Community.fetch_post(context, post_id),
         true <- visible?(post, club, context.user_id) || {:error, :not_found} do
      {:ok, club, post}
    end
  end

  defp visible?(%{hidden_at: nil}, _club, _user_id), do: true

  defp visible?(post, club, user_id),
    do: post.author_id == user_id or Community.can_moderate?(club.role)

  defp reload(context, club, post_id) do
    with {:ok, post} <- Community.fetch_post(context, post_id) do
      [presented] = PostPresenter.posts([post], [club], context.user_id)
      {:ok, presented}
    end
  end

  defp channel(club, channel_id) do
    case Enum.find(club.channels, &(&1.id == channel_id)) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
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
