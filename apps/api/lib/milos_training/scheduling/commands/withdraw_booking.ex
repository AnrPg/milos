defmodule MilosTraining.Scheduling.Commands.WithdrawBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id), do: SchedulingStore.withdraw_booking(id)
end
