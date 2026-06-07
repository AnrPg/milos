defmodule MilosTraining.TestSupport.FailingTokenIssuer do
  @behaviour MilosTraining.Application.Ports.TokenIssuer

  @impl true
  def issue_pair(_user), do: {:error, :simulated_failure}
end
