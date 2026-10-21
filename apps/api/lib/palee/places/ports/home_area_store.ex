defmodule Palee.Places.Ports.HomeAreaStore do
  @moduledoc "A person's «Η περιοχή μου» (ADR-154); every call is the context user's own."

  @callback list(context :: map()) :: [map()]
  @callback replace(context :: map(), neighbourhood_ids :: [binary()], DateTime.t()) ::
              :ok | {:error, term()}
end
