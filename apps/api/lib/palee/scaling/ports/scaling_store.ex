defmodule Palee.Scaling.Ports.ScalingStore do
  @moduledoc "Persistence port of the Scaling context (ADR-174). Every call runs in the gym's scope."

  @type context :: map()

  @callback get(context(), binary()) :: map() | nil
  @callback latest_live(context(), binary(), binary()) :: map() | nil
  @callback insert(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback replace(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback update(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback list(context(), map()) :: [map()]
  @callback approved_for_member(context(), binary(), binary(), Date.t()) :: map() | nil
  @callback approved_history(context(), binary(), pos_integer()) :: [map()]
end
