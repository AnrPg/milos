defmodule Palee.Execution.Commands.VoidTrainingLogEntry do
  @moduledoc """
  Voids (never deletes) a training-log entry owned by `user_id`.

  Voiding is idempotent from the caller's perspective: voiding an already
  voided entry returns `{:error, :training_log_entry_voided}` without
  changing it.
  """

  alias Palee.Execution.Commands.UpdateTrainingLogEntry
  alias Palee.Execution.Domain.TrainingLogPolicy
  alias Palee.Execution.TrainingLogStore

  def call(entry_id, user_id, params, %DateTime{} = now) do
    with %{} = entry <- TrainingLogStore.get_entry(entry_id) || {:error, :not_found},
         :ok <- TrainingLogPolicy.ensure_editable(entry, user_id),
         {:ok, expected_version} <- UpdateTrainingLogEntry.expected_version(params),
         {:ok, attrs} <-
           TrainingLogPolicy.void_attrs(params["reason"] || params[:reason], now) do
      TrainingLogStore.void_entry(entry_id, attrs, expected_version)
    end
  end
end
