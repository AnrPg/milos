defmodule MilosTraining.Places.Ports.GazetteerStore do
  @moduledoc "The neighbourhood and city gazetteer (ADR-154): public reference data."

  @type place :: %{
          id: binary(),
          slug: String.t(),
          kind: String.t(),
          name: String.t(),
          name_en: String.t(),
          city_slug: String.t() | nil,
          latitude: float(),
          longitude: float(),
          radius_m: pos_integer()
        }

  @doc "Places whose search key contains `normalized_query`; cities and prefix matches first."
  @callback search(normalized_query :: String.t(), limit :: pos_integer()) :: [place()]
  @callback get_many(ids :: [binary()]) :: [place()]
  @doc "The neighbourhood nearest to a point, within its reach (or a few kilometres)."
  @callback nearest({float(), float()}) :: place() | nil
end
