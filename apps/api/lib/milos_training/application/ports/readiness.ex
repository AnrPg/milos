defmodule MilosTraining.Application.Ports.Readiness do
  @callback status() :: {:ok, map()} | {:error, map()}
end
