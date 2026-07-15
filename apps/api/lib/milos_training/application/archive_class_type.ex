defmodule MilosTraining.Application.ArchiveClassType do
  alias MilosTraining.Scheduling

  def call(id, replacement_id),
    do: Scheduling.archive_class_type(id, blank_to_nil(replacement_id))

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
