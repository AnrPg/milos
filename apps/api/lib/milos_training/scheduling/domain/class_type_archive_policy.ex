defmodule MilosTraining.Scheduling.Domain.ClassTypeArchivePolicy do
  @moduledoc "Pure validation for historicity-preserving class type archival."

  def validate(_future_count, _source_id, _replacement_id, active_ids)
      when length(active_ids) <= 1,
      do: {:error, :last_active_class_type}

  def validate(0, _source_id, _replacement_id, _active_ids), do: :ok

  def validate(future_count, _source_id, nil, _active_ids) when future_count > 0,
    do: {:error, :class_type_replacement_required}

  def validate(future_count, source_id, replacement_id, active_ids) when future_count > 0 do
    if replacement_id != source_id and replacement_id in active_ids do
      :ok
    else
      {:error, :invalid_class_type_replacement}
    end
  end
end
