defmodule Palee.Application.BoxSearch do
  @moduledoc """
  ADR-221: find a box or an independent coach by name, in the member's
  personal session (the «Βρες» search, next to clubs and people).

  Only businesses a visitor may see answer: active, live (not in demo,
  ADR-184) and with a published public page (ADR-142). A location is not
  needed: Γύρω μου finds a business by where it is, this by what it is
  called. The query is folded like a person's name (accents and case do
  not matter) and also tried in its Latin form, which is how slugs are
  written (ADR-170), so "tolaras" finds «Τολάρας».
  """

  alias Palee.{Community, Identity, Organizations, Transliteration}

  @limit 20
  @min_length 2

  def call(%{user_id: user_id} = context, query) do
    query = String.trim(query || "")

    if String.length(query) < @min_length do
      {:ok, %{boxes: []}}
    else
      boxes = query |> terms() |> Organizations.search_public_boxes(@limit)
      ids = Enum.map(boxes, & &1.organization_id)
      mine = Community.follow_statuses(context, user_id, "organization", ids)

      {:ok,
       %{
         boxes:
           Enum.map(boxes, fn box ->
             Map.put(box, :my_status, Map.get(mine, box.organization_id, "none"))
           end)
       }}
    end
  end

  @doc "The folded query and its Latin form, each also hyphenated as slugs are, without repeats."
  def terms(query) do
    {_handle, folded} = Identity.people_search_terms(query)

    spellings = [folded, Transliteration.latin(folded)]

    (spellings ++ Enum.map(spellings, &String.replace(&1, " ", "-")))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
