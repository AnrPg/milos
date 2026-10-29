defmodule Palee.Setup.Ports.BusinessConfigurator do
  @moduledoc """
  How a setup recipe reaches the rest of Palee (ADR-255). Setup never writes
  another context's tables: the adapter reads the business's current state
  and applies each planned change through the application service that owns
  it (Scheduling, Finance, Gamification, Facility, Community, Trials,
  Organizations), with the caller's tenant context and permissions.

  `snapshot/1` returns the map `Palee.Setup.Domain.RecipePlan` documents.
  `apply_change/2` takes one change of a plan; it returns `:ok`, or an error
  that rolls the whole application back.
  """

  @type context :: map()
  @type change :: map()

  @callback snapshot(context()) :: {:ok, map()} | {:error, term()}
  @callback apply_change(context(), change()) :: :ok | {:error, term()}
  @doc "Called once after a committed application (caches, sync broadcasts)."
  @callback after_apply(context()) :: :ok
end
