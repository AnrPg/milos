defmodule MilosTraining.Scheduling.Queries.GetCalendarWeek do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(%{start_at: %DateTime{} = start_at, end_at: %DateTime{} = end_at} = params) do
    SchedulingStore.list_slots_window(start_at, end_at, params)
  end
end
