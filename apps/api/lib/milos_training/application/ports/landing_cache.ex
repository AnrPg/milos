defmodule MilosTraining.Application.Ports.LandingCache do
  @callback get_or_fetch(map(), Ecto.UUID.t(), (-> map())) :: map() | {:error, atom()}
  @callback batch_invalidate([Ecto.UUID.t()]) :: :ok
end
