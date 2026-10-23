defmodule Palee.Interests.Ports.InterestsStore do
  @moduledoc "A person's own interests (ADR-183); every call is the context user's own."

  @callback get(context :: map()) :: %{disciplines: [String.t()], level: String.t() | nil} | nil
  @callback put(context :: map(), attrs :: map(), DateTime.t()) ::
              {:ok, %{disciplines: [String.t()], level: String.t() | nil}} | {:error, term()}
end
