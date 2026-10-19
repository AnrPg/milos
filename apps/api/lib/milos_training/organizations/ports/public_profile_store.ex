defmodule MilosTraining.Organizations.Ports.PublicProfileStore do
  @moduledoc "Persistence port of gym public profiles (ADR-142)."

  @callback get(context :: map()) :: map() | nil
  @callback upsert(context :: map(), params :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_suggestion(context :: map(), params :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback pending_suggestions() :: [map()]
  @callback resolve_suggestion(id :: String.t(), status :: String.t()) ::
              :ok | {:error, :not_found}
end
