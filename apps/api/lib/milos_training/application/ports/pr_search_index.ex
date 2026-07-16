defmodule MilosTraining.Application.Ports.PRSearchIndex do
  @callback enqueue_upsert(map()) :: :ok | {:error, term()}
  @callback enqueue_delete(Ecto.UUID.t()) :: :ok | {:error, term()}
  @callback search(Ecto.UUID.t(), String.t()) :: {:ok, [Ecto.UUID.t()]} | {:error, term()}
end
