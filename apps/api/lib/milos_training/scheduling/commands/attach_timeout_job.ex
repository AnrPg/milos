defmodule MilosTraining.Scheduling.Commands.AttachTimeoutJob do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, booking_id, job_id),
    do: SchedulingStore.attach_timeout_job(context, booking_id, job_id)

  def call(booking_id, job_id), do: SchedulingStore.attach_timeout_job(booking_id, job_id)
end
