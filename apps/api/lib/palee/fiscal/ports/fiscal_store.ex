defmodule Palee.Fiscal.Ports.FiscalStore do
  @moduledoc """
  Persistence of the Fiscal context (ADR-240–242). Every callback takes the
  tenant context first; the facade (`Palee.Fiscal.FiscalStore`) opens the
  tenant session.

  Documents, lines, journal entries and closings are insert-only. Appending
  to the journal and taking a number happen under row locks
  (`lock_journal_head/1`, `next_sequence/2`) inside `transaction/2`, so
  a document, its number and its journal entry commit or roll back
  together.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type result(value) :: {:ok, value} | {:error, term()}

  @doc "Runs `fun` in one tenant transaction; `{:error, reason}` from it rolls everything back."
  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) :: result(term())

  # Identity
  @callback get_identity(context()) :: map() | nil
  @callback save_identity(context(), map()) :: result(map())

  # Who manages the connections (ADR-273)
  @doc "`%{managed_by, updated_by_id, updated_at}` or nil (no row: the owner)."
  @callback get_connection_setting(context()) :: map() | nil
  @callback save_connection_setting(context(), map()) :: result(map())

  # Journal
  @doc "Locks and returns the journal head `%{position, hash}` (creating it at position 0)."
  @callback lock_journal_head(context()) :: %{position: non_neg_integer(), hash: String.t()}
  @doc "Inserts an entry and moves the head to it (call after `lock_journal_head/1`)."
  @callback insert_journal_entry(context(), map()) :: result(map())
  @callback list_journal_entries(context(), %{
              optional(:after_position) => non_neg_integer(),
              optional(:limit) => pos_integer(),
              optional(:from) => DateTime.t(),
              optional(:to) => DateTime.t()
            }) :: [map()]

  # Documents
  @doc "Locks the series' sequence row and returns the next value."
  @callback next_sequence(context(), String.t()) :: pos_integer()
  @callback insert_document(context(), map(), [map()]) :: result(map())
  @callback get_document(context(), id(), keyword()) :: map() | nil
  @callback get_document_by_idempotency_key(context(), String.t()) :: map() | nil
  @callback list_documents(context(), map()) :: %{documents: [map()], total: non_neg_integer()}
  @doc "Credit notes so far per original line position: `%{position => %{quantity, amount_cents}}`."
  @callback credited_lines(context(), id()) :: %{pos_integer() => map()}
  @callback documents_between(context(), Date.t(), Date.t()) :: [map()]
  @callback first_issue_date(context()) :: Date.t() | nil

  # Closings
  @doc "The latest closing of each kind: `%{\"day\" => closing, ...}`."
  @callback latest_closings(context()) :: %{String.t() => map()}
  @callback insert_closing(context(), map()) :: result(map())
  @callback list_closings(context(), map()) :: [map()]

  @doc "Deletes all fiscal rows of the tenant (purge after retention only)."
  @callback purge(context()) :: result(%{String.t() => non_neg_integer()})
end
