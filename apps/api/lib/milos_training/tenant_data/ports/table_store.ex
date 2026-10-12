defmodule MilosTraining.TenantData.Ports.TableStore do
  @moduledoc """
  Generic executor for context-declared tenant table specs (ADR-107).

  Every call runs inside a `RepoContext` session opened by
  `MilosTraining.TenantData.TableStore`; `user_id` is `nil` for tables whose
  row security keys on `organization_id`, or the owning account for personal
  tables.
  """

  @type spec :: map()

  @callback count(spec(), Ecto.UUID.t(), Ecto.UUID.t() | nil) :: non_neg_integer()
  @callback export(spec(), Ecto.UUID.t(), Ecto.UUID.t() | nil) :: [map()]
  @callback delete(spec(), Ecto.UUID.t(), Ecto.UUID.t() | nil) :: non_neg_integer()
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
end
