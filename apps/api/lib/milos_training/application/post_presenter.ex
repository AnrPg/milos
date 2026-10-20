defmodule MilosTraining.Application.PostPresenter do
  @moduledoc """
  Posts and comments as the member app shows them (ADR-138, ADR-142): every
  post carries its origin (`club` › channel, or the author's `profile`), its
  audience, its author, and what the viewer may do with it.
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

  @doc """
  Public club posts of gyms the viewer may not belong to (box page,
  followed boxes): `boxes` are `Organizations.public_boxes/1` rows.
  """
  def public_box_posts(posts, boxes) do
    authors = authors(Enum.map(posts, & &1.author_id))
    boxes_by_id = Map.new(boxes, &{&1.organization_id, &1})

    Enum.flat_map(posts, fn post ->
      case Map.get(boxes_by_id, post.organization_id) do
        nil ->
          []

        box ->
          club = %{
            id: post.club_id,
            kind: "gym",
            name: box.name,
            organization_slug: box.slug,
            logo_url: box.logo_url,
            primary_color: box.primary_color
          }

          [
            post
            |> base(authors)
            |> Map.merge(%{
              origin: "club",
              club: club,
              channel: nil,
              pinned: false,
              hidden: false,
              can_delete: false,
              can_moderate: false,
              can_pin: false,
              can_report: false
            })
          ]
      end
    end)
  end

  @doc "Posts to followers or to everyone, by their authors (ADR-142)."
  def profile_posts(posts, viewer_id) do
    authors = authors(Enum.map(posts, & &1.author_id))

    Enum.map(posts, fn post ->
      post
      |> base(authors)
      |> Map.merge(%{
        origin: "profile",
        club: nil,
        channel: nil,
        pinned: false,
        hidden: false,
        can_delete: post.author_id == viewer_id,
        can_moderate: false,
        can_pin: false,
        can_report: false
      })
    end)
  end

  @doc "Comments on a profile post: their author or the post's author removes them."
  def profile_comments(comments, post, viewer_id) do
    authors = authors(Enum.map(comments, & &1.author_id))

    Enum.map(comments, fn comment ->
      %{
        id: comment.id,
        post_id: comment.post_id,
        author: author(authors, comment.author_id),
        body: comment.body,
        inserted_at: comment.inserted_at,
        can_delete: viewer_id in [comment.author_id, post.author_id]
      }
    end)
  end

  @doc "Comments on a club post; `moderator?` is the viewer's standing in its channel."
  def comments(comments, club, viewer_id, moderator? \\ nil) do
    authors = authors(Enum.map(comments, & &1.author_id))
    moderator? = if is_nil(moderator?), do: Community.can_moderate?(club.role), else: moderator?

    Enum.map(comments, fn comment ->
      %{
        id: comment.id,
        post_id: comment.post_id,
        author: author(authors, comment.author_id),
        body: comment.body,
        inserted_at: comment.inserted_at,
        hidden: not is_nil(Map.get(comment, :hidden_at)),
        can_delete: comment.author_id == viewer_id or moderator?,
        can_moderate: moderator?,
        can_report: comment.author_id != viewer_id
      }
    end)
  end

  defp present(post, club, authors, viewer_id) do
    channel = Enum.find(club.channels, &(&1.id == post.channel_id)) || %{kind: nil, name: nil}

    role =
      if is_map_key(channel, :id), do: Community.channel_role(club.role, channel), else: club.role

    post
    |> base(authors)
    |> Map.merge(%{
      origin: "club",
      club: %{
        id: club.id,
        kind: club.kind,
        name: club.name,
        organization_slug: club.organization_slug,
        logo_url: club.logo_url,
        primary_color: club.primary_color
      },
      channel: %{id: post.channel_id, kind: channel.kind, name: channel.name},
      pinned: not is_nil(post.pinned_at),
      hidden: not is_nil(post.hidden_at),
      can_delete: Community.can_delete_post?(post, viewer_id, role),
      can_moderate: Community.can_moderate?(role),
      can_pin: is_map_key(channel, :write_policy) and Community.can_pin?(channel, role),
      can_report: post.author_id != viewer_id
    })
  end

  defp base(post, authors) do
    %{
      id: post.id,
      audience: Map.get(post, :audience, "club_channel"),
      author: author(authors, post.author_id),
      body: post.body,
      attachment_type: post.attachment_type,
      attachment_id: post.attachment_id,
      attachment: public_snapshot(post.attachment),
      # The live event card, filled by EventCards where the feed is read (ADR-153).
      event: nil,
      kudos_count: post.kudos_count,
      comment_count: post.comment_count,
      kudos_by_me: post.kudos_by_me,
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
