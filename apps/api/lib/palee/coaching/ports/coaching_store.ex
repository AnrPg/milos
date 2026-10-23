defmodule Palee.Coaching.Ports.CoachingStore do
  @callback get_aggregates() :: map()
  @callback get_aggregates_for_users([String.t()]) :: map()
  @callback refresh_aggregates() :: :ok | {:error, term()}
end
