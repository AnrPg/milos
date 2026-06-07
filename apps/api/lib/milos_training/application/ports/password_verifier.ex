defmodule MilosTraining.Application.Ports.PasswordVerifier do
  @callback verify(String.t(), String.t()) :: boolean()
  @callback no_user_verify() :: term()
end
