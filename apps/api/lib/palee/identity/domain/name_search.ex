defmodule Palee.Identity.Domain.NameSearch do
  @moduledoc """
  ADR-187: the hidden search key of a profile. Holds the display name folded
  in its own script (lowercase, accents stripped) and, where a transliteration
  table exists, its Latin form, plus the handle. So "tolaras", "τολαρας" and
  "Tolaras" all find "Τολάρας", and a Chinese or Arabic name is found by
  typing it in its own script. Queries are folded the same way. Pure.
  """

  def key(display_name, handle) do
    folded = fold(display_name || "")

    [folded, Palee.Transliteration.latin(folded), handle || ""]
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  @doc """
  In-memory match of an account-like map against a typed query: its @handle
  (query folded to handle form) or its search key / display name (query
  folded as a name). An empty query matches everything.
  """
  def matches?(_person, query) when query in [nil, ""], do: true

  def matches?(person, query) when is_binary(query) do
    handle_query = Palee.Identity.Domain.Handle.normalize(query)
    name_query = fold(query)
    handle = Map.get(person, :handle) || Map.get(person, :normalized_nickname) || ""

    key =
      Map.get(person, :search_text) ||
        key(Map.get(person, :nickname) || "", handle)

    (handle_query != "" and String.contains?(handle, handle_query)) or
      (name_query != "" and String.contains?(key, name_query))
  end

  @doc "Folds a name or a query: NFKD, marks stripped, lowercased, spaces collapsed."
  def fold(value) when is_binary(value) do
    value
    |> String.normalize(:nfkd)
    |> String.replace(~r/\p{M}/u, "")
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.normalize(:nfc)
  end

  def fold(_value), do: ""
end
