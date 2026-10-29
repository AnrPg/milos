defmodule Palee.Setup.Ports.RecipeApplicationStore do
  @moduledoc """
  The record of applied setup recipes (ADR-255): which recipe and version,
  when, by whom and what it changed. Insert-only.

  `transaction/2` runs the whole application in one database transaction
  holding a per-business lock, so two owners applying at once cannot both
  create the same package or class type.
  """

  @type context :: map()

  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
  @callback insert(context(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Applications, newest first."
  @callback list(context(), limit :: pos_integer()) :: [map()]
end
