defmodule Palee.Coaching.Ports.RelationshipStore do
  @moduledoc "Persistence port for coaching relationships (ADR-100)."

  @callback start(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback finish(map(), binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
  @callback list(map(), map()) :: [map()]
  @callback active?(map(), binary(), binary()) :: boolean()
  @callback client_ids(map(), binary()) :: [binary()]
end
