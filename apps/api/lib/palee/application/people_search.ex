defmodule Palee.Application.PeopleSearch do
  @moduledoc """
  ADR-193 §4: people search across Palee, by @handle or display name, in the
  member's personal session. Ranked: people sharing a gym or open club,
  Buddies, other follows, public people nearby, then anyone public. Private
  people, or people who left search, show up only through a relation the
  viewer already has; demo people and blocks (either way) never do.
  """

  alias Palee.{Community, Identity}

  @limit 20

  def call(%{user_id: user_id} = context, query) do
    query = String.trim(query || "")
    {handle_term, name_term} = Identity.people_search_terms(query)

    if String.length(query) < 2 do
      {:ok, %{people: []}}
    else
      found = Community.search_people(context, handle_term, name_term, @limit)
      ids = Enum.map(found, &elem(&1, 0))
      people = ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
      mine = Community.follow_statuses(context, user_id, "user", ids)

      {:ok,
       %{
         people:
           Enum.flat_map(found, fn {id, relation} ->
             case Map.get(people, id) do
               nil ->
                 []

               person ->
                 [
                   %{
                     id: id,
                     nickname: person.nickname,
                     handle: Map.get(person, :handle),
                     avatar_url: Map.get(person, :avatar_url),
                     relation: relation,
                     my_status: Map.get(mine, id, "none"),
                     buddy: relation == "buddy"
                   }
                 ]
             end
           end)
       }}
    end
  end
end
