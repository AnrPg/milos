defmodule Palee.Application.RegisterUser do
  @moduledoc """
  Public sign-up (ADR-187). ADR-211: an email that already has a login,
  with a password that is not that login's, gets the answer a new sign-up
  gets (`{:confirmation_sent, email}`, "we sent a link"), with nothing
  created and no session (`SignUpWithExistingEmail`). The right password
  still adds a profile to the login, within the limit.
  """
  alias Palee.Identity
  alias Palee.Application.{RegisterProfile, TokenIssuer}

  def call(params) do
    with {:ok, user} <- register_profile(params),
         {:ok, tokens} <- issue_tokens_or_cleanup(user) do
      {:ok, Map.put(tokens, :user, user)}
    end
  end

  defp register_profile(params) do
    case RegisterProfile.call(params) do
      {:error, {:email_in_use, _count}} -> Palee.Application.SignUpWithExistingEmail.call(params)
      result -> result
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
