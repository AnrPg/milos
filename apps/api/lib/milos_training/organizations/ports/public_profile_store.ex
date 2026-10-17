defmodule MilosTraining.Organizations.Ports.PublicProfileStore do
  @moduledoc "Persistence port of gym public profiles (ADR-142)."

  @callback get(context :: map()) :: map() | nil
  @callback upsert(context :: map(), params :: map()) :: {:ok, map()} | {:error, term()}
end
