defmodule Palee.Community.Domain.FeedFilter do
  @moduledoc """
  The Feed and club Ροή filters beyond club and channel (vision §7.2,
  ADR-197): post `types` and `coaches_only`. Pure: callers pass the clubs
  in scope and each gym's staff.

  * **Types** are `announcement` (a post in a club's #ανακοινώσεις), `pr`
    (a shared PR) and `event` (an event's card); several widen each other.
  * **Coaches only** keeps posts whose author is staff (owner, admin or
    coach) of the gym that runs the club.

  Both narrow to club posts: profile posts and followed boxes' public posts
  carry neither a club channel nor a club role, so a narrowed feed leaves
  them out.
  """

  @types ~w(announcement pr event)

  def types, do: @types

  @doc "The requested types and coaches-only flag; unknown types are ignored."
  def parse(params) when is_map(params) do
    types =
      params
      |> value(:types)
      |> List.wrap()
      |> Enum.flat_map(&split/1)

    %{
      types: Enum.filter(@types, &(&1 in types)),
      coaches_only: truthy?(value(params, :coaches_only))
    }
  end

  def parse(_params), do: %{types: [], coaches_only: false}

  @doc "Whether the filter narrows anything."
  def active?(%{types: types, coaches_only: coaches_only}), do: types != [] or coaches_only

  @doc """
  What the post store needs: `kinds` (announcement channel ids and
  attachment types, any of which matches) and `authors` (staff ids per
  organization). Each is nil when it does not narrow. `staff_by_organization`
  is only read for coaches-only.
  """
  def narrowing(%{types: types, coaches_only: coaches_only}, clubs, staff_by_organization) do
    %{
      kinds: if(types != [], do: kinds(types, clubs)),
      authors: if(coaches_only, do: staff_by_organization)
    }
  end

  @doc "Whether one post (e.g. a pinned one) passes a narrowing."
  def keep?(post, %{kinds: kinds, authors: authors}) do
    kind_ok? =
      is_nil(kinds) or post.channel_id in kinds.channel_ids or
        post.attachment_type in kinds.attachment_types

    author_ok? =
      is_nil(authors) or post.author_id in Map.get(authors, post.organization_id, [])

    kind_ok? and author_ok?
  end

  defp kinds(types, clubs) do
    announcement_ids =
      if "announcement" in types,
        do:
          for(
            club <- clubs,
            channel <- club.channels,
            channel.kind == "announcements",
            do: channel.id
          ),
        else: []

    %{
      channel_ids: announcement_ids,
      attachment_types: Enum.filter(~w(pr event), &(&1 in types))
    }
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp split(value) when is_binary(value), do: String.split(value, ",", trim: true)
  defp split(_value), do: []

  defp truthy?(value), do: value in [true, "true", "1"]
end
