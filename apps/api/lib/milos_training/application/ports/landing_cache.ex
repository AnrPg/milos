defmodule MilosTraining.Application.Ports.LandingCache do
  @callback get_or_fetch(Ecto.UUID.t(), (-> map())) :: map()
  @callback batch_invalidate([Ecto.UUID.t()]) :: :ok
end
