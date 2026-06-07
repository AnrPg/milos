defmodule MilosTraining.Infrastructure.Auth.GuardianTokenIssuer do
  @behaviour MilosTraining.Application.Ports.TokenIssuer

  alias MilosTraining.Infrastructure.Auth.Guardian

  @impl true
  def issue_pair(user) do
    with {:ok, access_token, _} <- Guardian.encode_and_sign(user, %{}, token_type: "access"),
         {:ok, refresh_token, _} <- Guardian.encode_and_sign(user, %{}, token_type: "refresh") do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end
end
