defmodule MilosTraining.Scheduling.Commands.ArchiveClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, replacement_id), do: SchedulingStore.archive_class_type(id, replacement_id)
end
