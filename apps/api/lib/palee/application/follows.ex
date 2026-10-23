defmodule Palee.Application.Follows do
  @moduledoc """
  ADR-142 (P2-M2, D3): following people, boxes and (from P2-M4) open clubs.
  A follow of a person is a request they accept or decline; a published box
  is followed at once. Runs in the member's personal session.
  """

  alias Palee.{Community, Identity, Notifications, Organizations}

  @page 50

  def follow(%{user_id: user_id} = context, type, target_id) do
    with {:ok, target_id} <- uuid(target_id),
         {:ok, follow, outcome} <-
           Community.follow(context, type, target_id, target(type, target_id, user_id)) do
      if outcome == :created and follow.status == "requested", do: notify_request(user_id, follow)
      {:ok, %{status: follow.status}}
    end
  end

  def unfollow(context, type, target_id) do
    with {:ok, target_id} <- uuid(target_id),
         true <- type in Community.follow_target_types() || {:error, :invalid_follow_target} do
      :ok = Community.unfollow(context, type, target_id)
      {:ok, %{status: "none"}}
    end
  end

  def status(context, type, target_id) do
    with {:ok, target_id} <- uuid(target_id),
         true <- type in Community.follow_target_types() || {:error, :invalid_follow_target},
         do: {:ok, %{status: Community.follow_status(context, type, target_id)}}
  end

  @doc "People waiting for the member to accept them, newest first."
  def requests(%{user_id: user_id} = context, params) do
    page(params, fn page ->
      Community.list_incoming_follows(context, "user", user_id, "requested", page)
    end)
    |> present_people(:user_id, context)
  end

  def accept(%{user_id: user_id} = context, follow_id, now \\ DateTime.utc_now()) do
    with {:ok, follow} <- Community.accept_follow(context, follow_id, now) do
      notify_accepted(user_id, follow)
      :ok
    end
  end

  @doc "Declines a request, or removes a follower; either way the row goes."
  def remove(context, follow_id) do
    with {:ok, _follow} <- Community.remove_incoming_follow(context, follow_id), do: :ok
  end

  @doc "The member's followers; `q` keeps those whose name contains it."
  def followers(%{user_id: user_id} = context, params) do
    page(params, :user_id, &people_names/1, fn page ->
      Community.list_incoming_follows(context, "user", user_id, "active", page)
    end)
    |> present_people(:user_id, context)
  end

  @doc """
  What the member follows: `type` `user` (people) or `organization` (boxes);
  `q` keeps those whose name contains it.
  """
  def following(%{user_id: user_id} = context, params) do
    type = params[:type] || params["type"] || "user"

    with true <- type in ~w(user organization) || {:error, :invalid_follow_target} do
      result =
        page(params, :target_id, names_for(type), fn page ->
          Community.list_outgoing_follows(context, user_id, [type], ~w(requested active), page)
        end)

      case type do
        "user" -> present_people(result, :target_id, context)
        "organization" -> present_boxes(result)
      end
    end
  end

  # ADR-184: a mock person cannot be followed from outside its demo business.
  defp target("user", id, follower_id) do
    case Identity.find_by_id(id) do
      %{id: id} -> if Identity.visible_to?(id, follower_id), do: %{id: id}
      _missing -> nil
    end
  end

  defp target("organization", id, _follower_id) do
    case Organizations.public_boxes([id]) do
      [box] -> box
      _missing -> nil
    end
  end

  # Open clubs are followable from P2-M4.
  defp target(_type, _id, _follower_id), do: nil

  defp page(params, fetch), do: page(params, nil, nil, fetch)

  defp page(params, key, names, fetch) do
    with {:ok, before} <- Community.decode_feed_cursor(params[:cursor] || params["cursor"]) do
      among = among(search(params), key, names, fetch)
      rows = fetch.(Map.merge(%{before: before, limit: @page + 1}, among))
      {page, rest} = Enum.split(rows, @page)

      {:ok, page,
       if(rest != [] and page != [], do: Community.encode_feed_cursor(List.last(page)))}
    end
  end

  # Board 5 Q4: each connections list has a search. Names live in Identity
  # and Organizations, so the member's own follows are matched here and the
  # page is then read among the matches.
  defp among(nil, _key, _names, _fetch), do: %{}

  defp among(query, key, names, fetch) do
    ids = fetch.(%{limit: :all}) |> Enum.map(&Map.fetch!(&1, key))
    folded = fold(query)

    matches =
      for {id, name} <- names.(ids), name && String.contains?(fold(name), folded), do: id

    %{among: matches}
  end

  defp search(params) do
    case String.trim(params[:q] || params["q"] || "") do
      "" -> nil
      query -> query
    end
  end

  defp names_for("user"), do: &people_names/1
  defp names_for("organization"), do: &box_names/1

  defp people_names(ids), do: Enum.map(Identity.list_by_ids(ids), &{&1.id, &1.nickname})

  defp box_names(ids),
    do: Enum.map(Organizations.public_boxes(ids), &{&1.organization_id, &1.name})

  # Case- and accent-insensitive, so «μαρια» finds «Μαρία».
  defp fold(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  defp present_people({:ok, follows, cursor}, key, %{user_id: viewer_id} = context) do
    ids = Enum.map(follows, &Map.fetch!(&1, key))
    people = ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    mine = Community.follow_statuses(context, viewer_id, "user", ids)

    {:ok,
     %{
       entries:
         Enum.flat_map(follows, fn follow ->
           case Map.get(people, Map.fetch!(follow, key)) do
             nil ->
               []

             person ->
               [
                 %{
                   follow_id: follow.id,
                   status: follow.status,
                   since: follow.accepted_at || follow.inserted_at,
                   person: %{
                     id: person.id,
                     nickname: person.nickname,
                     avatar_url: Map.get(person, :avatar_url),
                     my_status: Map.get(mine, person.id, "none")
                   }
                 }
               ]
           end
         end),
       next_cursor: cursor
     }}
  end

  defp present_people(error, _key, _context), do: error

  defp present_boxes({:ok, follows, cursor}) do
    boxes =
      follows
      |> Enum.map(& &1.target_id)
      |> Organizations.public_boxes()
      |> Map.new(&{&1.organization_id, &1})

    {:ok,
     %{
       entries:
         Enum.flat_map(follows, fn follow ->
           case Map.get(boxes, follow.target_id) do
             nil ->
               []

             box ->
               [
                 %{
                   follow_id: follow.id,
                   status: follow.status,
                   since: follow.accepted_at || follow.inserted_at,
                   box: box
                 }
               ]
           end
         end),
       next_cursor: cursor
     }}
  end

  defp present_boxes(error), do: error

  defp notify_request(follower_id, follow) do
    Notifications.dispatch_event(:follow_requested, %{
      user_id: follow.target_id,
      follow_id: follow.id,
      follower_id: follower_id,
      follower_nickname: nickname(follower_id)
    })
  end

  defp notify_accepted(accepter_id, follow) do
    Notifications.dispatch_event(:follow_accepted, %{
      user_id: follow.user_id,
      follow_id: follow.id,
      person_id: accepter_id,
      person_nickname: nickname(accepter_id)
    })
  end

  defp nickname(user_id) do
    case Identity.find_by_id(user_id) do
      %{nickname: nickname} -> nickname
      _missing -> nil
    end
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
