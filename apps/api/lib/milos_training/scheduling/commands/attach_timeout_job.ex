defmodule MilosTraining.Scheduling.Commands.AttachTimeoutJob do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(booking_id, job_id), do: SchedulingStore.attach_timeout_job(booking_id, job_id)
end
