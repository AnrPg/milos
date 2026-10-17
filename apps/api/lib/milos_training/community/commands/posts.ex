defmodule MilosTraining.Community.Commands.Posts do
  @moduledoc """
  Posting, moderation, kudos and comments in a gym's club (ADR-138). The
  caller states the actor's club role (derived from their gym roles) and
  whether they joined the channel; governance comes from `ChannelPolicy`.
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.ChannelPolicy

  @doc "A post in `channel` by the context's user. `attachment` is an already built snapshot."
  def create(
        %{organization_id: organization_id, user_id: user_id} = context,
        channel,
        role,
        joined?,
        attrs
      ) do
    cond do
      channel.organization_id != organization_id ->
        {:error, :not_found}

      not ChannelPolicy.can_post?(channel, role, joined?) ->
        {:error, :cannot_post_in_channel}

      true ->
        CommunityStore.create_post(context, %{
          organization_id: organization_id,
          club_id: channel.club_id,
          channel_id: channel.id,
          author_id: user_id,
          audience: "club_channel",
          body: Map.get(attrs, :body),
          attachment_type: Map.get(attrs, :attachment_type),
          attachment_id: Map.get(attrs, :attachment_id),
          attachment: Map.get(attrs, :attachment),
          client_operation_id: Map.get(attrs, :client_operation_id)
        })
    end
  end

  def fetch(%{organization_id: organization_id, user_id: user_id} = context, post_id) do
    case CommunityStore.get_post(context, post_id, user_id) do
      %{organization_id: ^organization_id} = post -> {:ok, post}
      _missing -> {:error, :not_found}
    end
  end

  def delete(%{user_id: user_id} = context, post, role, now) do
    if ChannelPolicy.can_delete_post?(post, user_id, role),
      do: CommunityStore.moderate_post(context, post.id, %{deleted_at: now}),
      else: {:error, :forbidden}
  end

  def hide(%{user_id: user_id} = context, post, role, hidden?, now) do
    if ChannelPolicy.can_moderate?(role) do
      attrs =
        if hidden?,
          do: %{hidden_at: now, hidden_by_id: user_id},
          else: %{hidden_at: nil, hidden_by_id: nil}

      CommunityStore.moderate_post(context, post.id, attrs)
    else
      {:error, :forbidden}
    end
  end

  def pin(context, post, channel, role, pinned?, now) do
    if ChannelPolicy.can_pin?(channel, role),
      do: CommunityStore.moderate_post(context, post.id, %{pinned_at: if(pinned?, do: now)}),
      else: {:error, :forbidden}
  end

  def kudos(%{user_id: user_id} = context, post, true),
    do: CommunityStore.react(context, post, user_id, "kudos")

  def kudos(%{user_id: user_id} = context, post, false),
    do: CommunityStore.unreact(context, post, user_id, "kudos")

  def comment(%{user_id: user_id} = context, post, body) do
    CommunityStore.add_comment(context, %{
      organization_id: post.organization_id,
      post_id: post.id,
      author_id: user_id,
      body: body
    })
  end

  def delete_comment(
        %{user_id: user_id, organization_id: organization_id} = context,
        comment_id,
        role,
        now
      ) do
    case CommunityStore.get_comment(context, comment_id) do
      %{organization_id: ^organization_id} = comment ->
        if comment.author_id == user_id or ChannelPolicy.can_moderate?(role),
          do: CommunityStore.delete_comment(context, comment.id, now),
          else: {:error, :forbidden}

      _missing ->
        {:error, :not_found}
    end
  end
end
