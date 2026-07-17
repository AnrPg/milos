defmodule MilosTraining.Application.AddExecutionModifications do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.Domain.ModificationPatchValidator
  alias MilosTraining.Execution.ExecutionStore, as: ExStore

  def call(execution_id, user_id, modifications) do
    with execution when not is_nil(execution) <-
           Execution.get_execution_for_user(execution_id, user_id),
         {:ok, normalized} <- ModificationPatchValidator.normalize_many(modifications) do
      existing = execution.exercise_modifications || []
      logged_at = DateTime.to_iso8601(DateTime.utc_now())
      timestamped = Enum.map(normalized, &Map.put(&1, "logged_at", logged_at))
      merged = upsert_patches(existing, timestamped)
      ExStore.update_execution(execution_id, %{exercise_modifications: merged})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp upsert_patches(existing, incoming) do
    incoming
    |> Enum.reduce(existing, fn patch, acc ->
      patch_id = patch["patch_id"]

      case Enum.find_index(
             acc,
             &(Map.get(&1, "patch_id") == patch_id || Map.get(&1, :patch_id) == patch_id)
           ) do
        nil -> acc ++ [patch]
        index -> List.replace_at(acc, index, patch)
      end
    end)
  end
end
