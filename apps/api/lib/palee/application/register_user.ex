defmodule Palee.Application.RegisterUser do
  alias Palee.Identity
  alias Palee.Application.{EmailVerification, RegisterProfile, TokenIssuer}

  def call(params) do
    with {:ok, user} <- RegisterProfile.call(params),
         {:ok, tokens} <- issue_tokens_or_cleanup(user) do
      # ADR-213: a new login gets its verification link; nothing blocks on it.
      :ok = EmailVerification.after_sign_up(user)
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
