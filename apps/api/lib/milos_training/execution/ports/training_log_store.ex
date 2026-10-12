defmodule MilosTraining.Execution.Ports.TrainingLogStore do
  @moduledoc "Persistence port for standalone training-log entries (ADR-100)."

  @type entry :: map()
  @type write_error ::
          {:error, Ecto.Changeset.t()}
          | {:error, :not_found}
          | {:error, :organization_context_required}
          | {:error, :training_log_entry_voided}
          | {:error, :stale_training_log_entry}
          | {:error, :training_log_source_already_logged}
          | {:error, :completion_processing_unavailable}

  @callback create_entry(map(), (map() -> Ecto.Changeset.t()) | nil) ::
              {:ok, entry()} | write_error()
  @callback get_entry_by_idempotency_key(binary(), binary()) :: entry() | nil
  @callback update_entry(binary(), map(), integer() | nil) :: {:ok, entry()} | write_error()
  @callback void_entry(binary(), map(), integer() | nil) :: {:ok, entry()} | write_error()
  @callback get_entry(binary()) :: entry() | nil
  @callback list_entries_for_user(binary(), keyword()) :: [entry()]
  @callback list_live_source_reference_ids(binary(), binary()) :: [binary()]
end
