defmodule Palee.Places.Ports.WorldGazetteerSource do
  @moduledoc """
  Where the worldwide town list comes from (ADR-188): the GeoNames dump
  files as lines. Public reference data; nothing about people is sent.
  """

  @type lines :: Enumerable.t()

  @doc "The towns dump (one place per line), the admin1 names and the country list."
  @callback fetch() ::
              {:ok, %{places: lines(), admin1: lines(), countries: lines()}} | {:error, term()}
end
