defmodule MilosTraining.Identity.Ports.SavedFilterStore do
  @moduledoc "Persistence port of remembered filters (ADR-151); every call is the context user's own."

  @callback list(context :: map(), surface :: String.t()) :: [map()]
  @callback put_last_used(context :: map(), surface :: String.t(), params :: map(), DateTime.t()) ::
              {:ok, map()}
  @callback put_named(
              context :: map(),
              surface :: String.t(),
              name :: String.t(),
              params :: map(),
              DateTime.t()
            ) ::
              {:ok, map()} | {:error, term()}
  @callback count_named(context :: map(), surface :: String.t()) :: non_neg_integer()
  @callback delete_named(context :: map(), id :: binary()) :: :ok | {:error, :not_found}
end
