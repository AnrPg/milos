defmodule MilosTraining.Coaching.Ports.CoachingStore do
  @callback get_aggregates() :: map()
  @callback refresh_aggregates() :: :ok | {:error, term()}
end
