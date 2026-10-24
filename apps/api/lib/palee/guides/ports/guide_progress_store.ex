defmodule Palee.Guides.Ports.GuideProgressStore do
  @moduledoc "Persistence port of walkthrough progress (ADR-193); every call is the context user's own."

  @type progress :: %{
          guide_id: String.t(),
          version: pos_integer(),
          status: String.t(),
          step: non_neg_integer(),
          runs: pos_integer(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          updated_at: DateTime.t()
        }

  @typedoc """
  Decides the next row from the current one (nil when there is none) and,
  for a new row, how many guides the person already has. Answers the fields
  to write, or an error that leaves the row as it was.
  """
  @type change_fun :: (progress() | nil, non_neg_integer() -> {:ok, map()} | {:error, term()})

  @callback list(context :: map()) :: [progress()]
  @doc "Reads the row locked, applies `fun` and writes its answer, in one transaction."
  @callback update(context :: map(), guide_id :: String.t(), DateTime.t(), change_fun()) ::
              {:ok, progress()} | {:error, term()}
  @callback delete(context :: map(), guide_id :: String.t()) :: :ok
end
