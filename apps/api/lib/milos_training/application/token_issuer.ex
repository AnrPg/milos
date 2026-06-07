defmodule MilosTraining.Application.TokenIssuer do
  def issue_pair(user) do
    case impl().issue_pair(user) do
      {:ok, tokens} -> {:ok, tokens}
      {:error, _reason} -> {:error, :token_issuance_failed}
    end
  end

  defp impl do
    Application.fetch_env!(:milos_training, :token_issuer)
  end
end
