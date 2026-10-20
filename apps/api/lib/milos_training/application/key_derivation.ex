defmodule MilosTraining.Application.KeyDerivation do
  @moduledoc "Configured adapter of `Ports.KeyDerivation` (ADR-155)."
  @behaviour MilosTraining.Application.Ports.KeyDerivation

  @impl true
  def derive(purpose, material), do: impl().derive(purpose, material)

  defp impl, do: Application.fetch_env!(:milos_training, :key_derivation)
end
