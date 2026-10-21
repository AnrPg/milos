defmodule Palee.Execution.Ports.TrainingLogStore do
  @moduledoc "Persistence port for standalone training-log entries (ADR-118)."

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
  @callback list_entry_items(binary(), term(), pos_integer(), term()) :: [entry()]
  @callback set_entry_visibility(binary(), binary(), String.t()) ::
              {:ok, entry()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  @callback move_entries(binary(), [String.t()], String.t()) :: non_neg_integer()

  # ADR-138 D6: one gym's live entries of a workout in a window.
  @callback list_for_workout(binary(), binary(), DateTime.t(), DateTime.t()) :: [entry()]
end
