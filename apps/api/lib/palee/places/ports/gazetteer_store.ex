defmodule Palee.Places.Ports.GazetteerStore do
  @moduledoc "The neighbourhood and city gazetteer (ADR-154): public reference data."

  @type place :: %{
          id: binary(),
          slug: String.t(),
          kind: String.t(),
          name: String.t(),
          name_en: String.t(),
          city_slug: String.t() | nil,
          context: String.t() | nil,
          context_en: String.t() | nil,
          latitude: float(),
          longitude: float(),
          radius_m: pos_integer()
        }

  @doc """
  Places whose search key contains `normalized_query`, or resembles it
  (typos, trigram word similarity); prefix and word matches first, then
  bigger places.
  """
  @callback search(normalized_query :: String.t(), limit :: pos_integer()) :: [place()]
  @callback get_many(ids :: [binary()]) :: [place()]
  @doc "The neighbourhood nearest to a point, within its reach (or a few kilometres)."
  @callback nearest({float(), float()}) :: place() | nil
  @doc """
  Stores a geocoded place (ADR-188) under its slug and id, or refreshes the
  stored one's names and shape; curated places are never touched.
  """
  @callback import(map()) :: {:ok, place()} | {:error, term()}
  @doc "Upserts reference places of one source (ADR-188), by slug; returns how many."
  @callback upsert_many(source :: String.t(), places :: [map()]) :: non_neg_integer()
  @doc "When a source was last refreshed (its newest row), or nil when it has none."
  @callback refreshed_at(source :: String.t()) :: DateTime.t() | nil
  @doc "All places of one source (small sources only: curated, for de-duplication)."
  @callback list_source(source :: String.t()) :: [place()]
end
