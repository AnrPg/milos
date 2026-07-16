defmodule MilosTraining.Application.LogoutSession do
  alias MilosTraining.Application.{TokenStore, TokenVerifier}

  def call(nil), do: :ok

  def call(refresh_token) when is_binary(refresh_token) do
    with {:ok, claims} <- TokenVerifier.decode_refresh_token(refresh_token),
         {:ok, _consumed} <- TokenStore.consume(claims["jti"], ttl_ms(claims["exp"])) do
      :ok
    else
      _error -> :ok
    end
  end

  defp ttl_ms(exp) when is_integer(exp),
    do: max((exp - System.system_time(:second)) * 1_000, 1_000)

  defp ttl_ms(_exp), do: 1_000
end
