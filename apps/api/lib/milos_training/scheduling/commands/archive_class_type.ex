defmodule MilosTraining.Scheduling.Commands.ArchiveClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, id, replacement_id),
    do: SchedulingStore.archive_class_type(context, id, replacement_id)

  def call(id, replacement_id), do: SchedulingStore.archive_class_type(id, replacement_id)
end
