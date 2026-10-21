defmodule Palee.TestSupport.FailingTokenIssuer do
  @behaviour Palee.Application.Ports.TokenIssuer

  @impl true
  def issue_pair(_user), do: {:error, :simulated_failure}
end
