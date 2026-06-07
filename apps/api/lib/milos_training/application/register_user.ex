defmodule MilosTraining.Application.RegisterUser do
  alias MilosTraining.Identity
  alias MilosTraining.Application.TokenIssuer

  def call(params) do
    with {:ok, user} <- Identity.register(params),
         {:ok, tokens} <- issue_tokens_or_cleanup(user) do
      {:ok, Map.put(tokens, :user, user)}
    end
  end

  defp issue_tokens_or_cleanup(user) do
    case TokenIssuer.issue_pair(user) do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, :token_issuance_failed} ->
        case Identity.delete(user) do
          :ok -> {:error, :token_issuance_failed}
          {:error, _reason} -> {:error, :registration_cleanup_failed}
        end
    end
  end
end
