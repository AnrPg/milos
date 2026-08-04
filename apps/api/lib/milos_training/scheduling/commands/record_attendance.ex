defmodule MilosTraining.Scheduling.Commands.RecordAttendance do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, params), do: SchedulingStore.record_attendance(context, params)
  def call(params), do: SchedulingStore.record_attendance(params)
end
