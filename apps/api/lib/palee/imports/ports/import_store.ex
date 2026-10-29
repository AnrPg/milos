defmodule Palee.Imports.Ports.ImportStore do
  @moduledoc """
  Persistence of imports, their rows and the imported people (ADR-254).
  Every callback takes the tenant context first; reads and writes run under
  its Row Level Security.

  Applying a row happens in one transaction (`transaction/2`) that locks
  the row (`lock_row/2`), so two jobs never apply the same row; the partial
  unique index on applied fingerprints makes a second application of the
  same values fail even across imports.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}

  # Imports
  @doc "Inserts the import and its rows (`[%{row_number, cells}]`)."
  @callback insert_import(context(), map(), [map()]) :: {:ok, map()} | {:error, term()}
  @callback get_import(context(), id(), keyword()) :: map() | nil
  @callback list_imports(context(), map()) :: [map()]
  @callback update_import(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_import(context(), id()) :: :ok

  # Rows
  @doc "Rows by `row_number`; filters `status`, `outcome`, `after_row`, `limit`."
  @callback list_rows(context(), id(), map()) :: [map()]
  @doc "Saves the dry-run plan of many rows (`[%{row_number, outcome, ...}]`)."
  @callback save_plans(context(), id(), [map()]) :: :ok
  @callback lock_row(context(), id()) :: map() | nil
  @callback update_row(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Whether a row with this fingerprint is applied in the business."
  @callback applied_fingerprint?(context(), String.t()) :: boolean()
  @doc "`%{statuses: %{status => n}, outcomes: %{outcome => n}}` of an import's rows."
  @callback row_counts(context(), id()) :: map()

  # People
  @callback list_people(context()) :: [map()]
  @callback find_person(context(), :email | :phone_key | :user_id, String.t()) :: map() | nil
  @callback upsert_person(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_person(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "The people an import brought in or matched, with an email."
  @callback people_of_import(context(), id()) :: [map()]
end
