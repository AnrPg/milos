defmodule MilosTraining.Execution.Commands.UpdateTrainingLogEntry do
  @moduledoc """
  Owner edit of a live training-log entry. Source fields are immutable; only
  the performed details change. `expected_version` (optional) guards against
  lost updates from concurrent editors.
  """

  alias MilosTraining.Execution.Domain.TrainingLogPolicy
  alias MilosTraining.Execution.TrainingLogStore

  def call(entry_id, user_id, params, opts) do
    with %{} = entry <- TrainingLogStore.get_entry(entry_id) || {:error, :not_found},
         :ok <- TrainingLogPolicy.ensure_editable(entry, user_id),
         {:ok, expected_version} <- expected_version(params),
         {:ok, changes} <-
           TrainingLogPolicy.normalize_details(
             params,
             [
               now: Keyword.fetch!(opts, :now),
               structured?: is_binary(entry.master_workout_id),
               allowed_section_ids: Keyword.get(opts, :allowed_section_ids, []),
               freeform?: entry.source_type == "freeform"
             ],
             :update
           ) do
      TrainingLogStore.update_entry(entry_id, changes, expected_version)
    end
  end

  def expected_version(params) do
    case params["expected_version"] || params[:expected_version] do
      nil -> {:ok, nil}
      version when is_integer(version) and version > 0 -> {:ok, version}
      _invalid -> {:error, [expected_version: "is invalid"]}
    end
  end
end
