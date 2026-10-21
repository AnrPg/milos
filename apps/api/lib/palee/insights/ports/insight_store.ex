defmodule Palee.Insights.Ports.InsightStore do
  @moduledoc """
  Persistence port of the Insights context (ADR-166). Rows are the owner's
  alone: every call runs in that person's own session.
  """

  alias Palee.Insights.Insight

  @type id :: Ecto.UUID.t()

  @doc "The person's stored results, one per rule."
  @callback list(id()) :: [Insight.t()]

  @doc """
  Replaces each rule's result (`%{rule, status, value, fingerprint}`) for
  the window `from..to`, keeping the dismissal.
  """
  @callback put_results(id(), [map()], Date.t(), Date.t(), DateTime.t()) :: :ok

  @doc "Hides the rule's current finding until it changes."
  @callback dismiss(id(), String.t(), DateTime.t()) :: :ok | {:error, :not_found}

  @doc "Shows every dismissed finding again."
  @callback restore(id()) :: :ok

  @doc "Forgets every result (the data behind them was erased)."
  @callback delete_all(id()) :: :ok

  @doc "People with recent data, by id after `after_id` (ids only, definer lookup)."
  @callback candidates(DateTime.t(), id() | nil, pos_integer()) :: [id()]
end
