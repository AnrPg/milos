defmodule Palee.Application.LoginUser do
  @moduledoc """
  Sign-in with an email or an @handle and the login's password (ADR-187).
  A handle opens that profile; an email opens the profile used last on that
  login. Either way the profile becomes the login's last used one.
  """
  alias Palee.Identity
  alias Palee.Application.PasswordVerifier
  alias Palee.Application.TokenIssuer

  def call(params) when is_map(params) do
    identifier = value(params, :identifier) || value(params, :nickname)
    password = value(params, :password)

    with true <- is_binary(identifier) and is_binary(password),
         %{} = user <- find(identifier),
         true <- PasswordVerifier.verify(password, user.password_hash),
         {:ok, tokens} <- TokenIssuer.issue_pair(user) do
      :ok = Identity.touch_last_used(user.login_id, user.id)
      {:ok, Map.put(tokens, :user, user)}
    else
      nil ->
        PasswordVerifier.no_user_verify()
        {:error, :invalid_credentials}

      false ->
        {:error, :invalid_credentials}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find(identifier) do
    identifier = String.trim(identifier)

    if String.contains?(identifier, "@") and not String.starts_with?(identifier, "@"),
      do: Identity.find_by_email(identifier),
      else: Identity.find_by_handle(identifier)
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
