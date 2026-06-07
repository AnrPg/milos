defmodule MilosTraining.Application.LoginUser do
  alias MilosTraining.Identity
  alias MilosTraining.Application.PasswordVerifier
  alias MilosTraining.Application.TokenIssuer

  def call(params) when is_map(params) do
    nickname =
      params
      |> Map.get("nickname")
      |> Kernel.||(Map.get(params, :nickname))
      |> normalize_nickname()

    password = Map.get(params, "password") || Map.get(params, :password)

    with true <- is_binary(nickname) and is_binary(password),
         %{} = user <- Identity.find_by_nickname(nickname),
         true <- PasswordVerifier.verify(password, user.password_hash),
         {:ok, tokens} <- TokenIssuer.issue_pair(user) do
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

  defp normalize_nickname(nil), do: nil

  defp normalize_nickname(nickname) when is_binary(nickname),
    do: nickname |> String.trim() |> String.downcase()
end
