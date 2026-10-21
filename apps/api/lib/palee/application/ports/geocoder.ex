defmodule Palee.Application.Ports.Geocoder do
  @moduledoc """
  Turns an address into places on the map and a map point back into an
  address (ADR-141). Admins use it to pin a location; results are only
  suggestions, the admin confirms what is saved.
  """

  @type place :: %{
          label: String.t(),
          address: String.t() | nil,
          neighbourhood: String.t() | nil,
          city: String.t() | nil,
          country_code: String.t() | nil,
          latitude: float(),
          longitude: float()
        }

  @type opts :: [language: String.t() | nil, near: {float(), float()} | nil, limit: pos_integer()]

  @callback search(String.t(), opts()) :: {:ok, [place()]} | {:error, term()}
  @callback reverse(float(), float(), opts()) :: {:ok, place() | nil} | {:error, term()}
end
