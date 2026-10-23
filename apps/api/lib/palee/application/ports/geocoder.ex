defmodule Palee.Application.Ports.Geocoder do
  @moduledoc """
  Turns an address into places on the map and a map point back into an
  address (ADR-141). Admins use it to pin a location; results are only
  suggestions, the admin confirms what is saved. Members find neighbourhoods,
  towns and the area around an address anywhere in the world with it
  (ADR-188), which is what the optional keys and `layers` are for.
  """

  @type place :: %{
          optional(:name) => String.t() | nil,
          optional(:state) => String.t() | nil,
          optional(:country) => String.t() | nil,
          optional(:layer) => String.t() | nil,
          optional(:osm_ref) => String.t() | nil,
          optional(:osm_value) => String.t() | nil,
          optional(:extent) => [float()] | nil,
          required(:label) => String.t(),
          required(:address) => String.t() | nil,
          required(:neighbourhood) => String.t() | nil,
          required(:city) => String.t() | nil,
          required(:country_code) => String.t() | nil,
          required(:latitude) => float(),
          required(:longitude) => float()
        }

  @typedoc """
  `language: "default"` asks for local names. `layers` keeps only results of
  those kinds ("city", "district", "locality", "street", "house").
  """
  @type opts :: [
          language: String.t() | nil,
          near: {float(), float()} | nil,
          limit: pos_integer(),
          layers: [String.t()]
        ]

  @callback search(String.t(), opts()) :: {:ok, [place()]} | {:error, term()}
  @callback reverse(float(), float(), opts()) :: {:ok, place() | nil} | {:error, term()}
end
