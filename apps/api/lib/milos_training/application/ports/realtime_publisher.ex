defmodule MilosTraining.Application.Ports.RealtimePublisher do
  @callback broadcast(String.t(), String.t(), map()) :: :ok | {:error, term()}
end
