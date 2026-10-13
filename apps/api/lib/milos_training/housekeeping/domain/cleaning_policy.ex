defmodule MilosTraining.Housekeeping.Domain.CleaningPolicy do
  @moduledoc "Rules of the cleaning log (ADR-102)."

  def can_start?(%{archived_at: nil}), do: :ok
  def can_start?(_area), do: {:error, :cleaning_area_archived}

  @doc "Finishing keeps only the area's own tasks, in the area's order."
  def finish(entry, area, tasks_done, finished_at) do
    cond do
      not is_nil(entry.finished_at) ->
        {:error, :cleaning_already_finished}

      DateTime.compare(finished_at, entry.started_at) == :lt ->
        {:error, :cleaning_finished_before_start}

      true ->
        done = List.wrap(tasks_done)
        {:ok, Enum.filter(area.tasks, &(&1 in done))}
    end
  end
end
