defmodule MilosTraining.Pantheon.Domain.PRHistoryPolicy do
  @snapshot_fields ~w(name current_score unit higher_is_better beaten_on supporting_metrics notes)a

  @spec snapshot_required?(map()) :: boolean()
  def snapshot_required?(changes) when is_map(changes) do
    Enum.any?(@snapshot_fields, &Map.has_key?(changes, &1))
  end
end
