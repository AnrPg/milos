defmodule MilosTraining.Community.Commands.ProfilePosts do
  @moduledoc """
  Posts to followers or to everyone, with their kudos and comments
  (ADR-142). The author owns the post; RLS decides who reads it.
  """

  alias MilosTraining.Community.Domain.AudiencePolicy
  alias MilosTraining.Community.SocialStore

  def create(%{user_id: user_id} = context, audience, attrs) do
    if AudiencePolicy.profile_audience?(audience) do
      SocialStore.create_profile_post(context, %{
        user_id: user_id,
        audience: audience,
        body: Map.get(attrs, :body),
        attachment_type: Map.get(attrs, :attachment_type),
        attachment_id: Map.get(attrs, :attachment_id),
        attachment: Map.get(attrs, :attachment),
        client_operation_id: Map.get(attrs, :client_operation_id)
      })
    else
      {:error, :invalid_audience}
    end
  end

  def fetch(%{user_id: user_id} = context, post_id) do
    case SocialStore.get_profile_post(context, post_id, user_id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  def delete(%{user_id: user_id} = context, %{author_id: user_id} = post, now),
    do: SocialStore.delete_profile_post(context, post.id, now)

  def delete(_context, _post, _now), do: {:error, :forbidden}

  def kudos(%{user_id: user_id} = context, post, true),
    do: SocialStore.react_profile_post(context, post.id, user_id, "kudos")

  def kudos(%{user_id: user_id} = context, post, false),
    do: SocialStore.unreact_profile_post(context, post.id, user_id, "kudos")

  def comment(%{user_id: user_id} = context, post, body),
    do:
      SocialStore.add_profile_comment(context, %{post_id: post.id, user_id: user_id, body: body})

  @doc "A comment's author removes it, or the post's author does."
  def delete_comment(%{user_id: user_id} = context, comment_id, now) do
    with %{} = comment <- SocialStore.get_profile_comment(context, comment_id),
         {:ok, post} <- fetch(context, comment.post_id) do
      if user_id in [comment.author_id, post.author_id],
        do: SocialStore.delete_profile_comment(context, comment.id, now),
        else: {:error, :forbidden}
    else
      _missing -> {:error, :not_found}
    end
  end
end
