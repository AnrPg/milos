defmodule MilosTraining.Application.PostPresenter do
  @moduledoc """
  Posts and comments as the member app shows them (ADR-138): every post
  carries its origin (club › channel), its author, and what the viewer may
  do with it.
  """

  alias MilosTraining.{Community, Identity}

  def posts(posts, clubs, viewer_id) do
    authors = authors(Enum.map(posts, & &1.author_id))
    clubs_by_id = Map.new(clubs, &{&1.id, &1})

    Enum.flat_map(posts, fn post ->
      case Map.get(clubs_by_id, post.club_id) do
        nil -> []
        club -> [present(post, club, authors, viewer_id)]
      end
    end)
  end

  def comments(comments, club, viewer_id) do
    authors = authors(Enum.map(comments, & &1.author_id))

    Enum.map(comments, fn comment ->
      %{
        id: comment.id,
        post_id: comment.post_id,
        author: author(authors, comment.author_id),
        body: comment.body,
        inserted_at: comment.inserted_at,
        can_delete: comment.author_id == viewer_id or Community.can_moderate?(club.role)
      }
    end)
  end

  defp present(post, club, authors, viewer_id) do
    channel = Enum.find(club.channels, &(&1.id == post.channel_id)) || %{kind: nil, name: nil}

    %{
      id: post.id,
      club: %{
        id: club.id,
        name: club.name,
        organization_slug: club.organization_slug,
        logo_url: club.logo_url,
        primary_color: club.primary_color
      },
      channel: %{id: post.channel_id, kind: channel.kind, name: channel.name},
      author: author(authors, post.author_id),
      body: post.body,
      attachment_type: post.attachment_type,
      attachment_id: post.attachment_id,
      attachment: public_snapshot(post.attachment),
      pinned: not is_nil(post.pinned_at),
      hidden: not is_nil(post.hidden_at),
      kudos_count: post.kudos_count,
      comment_count: post.comment_count,
      kudos_by_me: post.kudos_by_me,
      can_delete: Community.can_delete_post?(post, viewer_id, club.role),
      can_moderate: Community.can_moderate?(club.role),
      can_pin: is_map_key(channel, :write_policy) and Community.can_pin?(channel, club.role),
      inserted_at: post.inserted_at
    }
  end

  # The rung the entry had before it was posted is the author's business.
  defp public_snapshot(nil), do: nil
  defp public_snapshot(snapshot), do: Map.drop(snapshot, ["previous_visibility"])

  defp authors(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    end
  end

  defp author(authors, id) do
    case Map.get(authors, id) do
      nil -> %{id: id, nickname: nil, avatar_url: nil}
      user -> %{id: id, nickname: user.nickname, avatar_url: Map.get(user, :avatar_url)}
    end
  end
end
