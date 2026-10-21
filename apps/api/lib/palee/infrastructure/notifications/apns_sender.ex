defmodule Palee.Infrastructure.Notifications.ApnsSender do
  @moduledoc """
  APNs adapter of `Notifications.Ports.NativePushSender` (ADR-171), for the
  iOS app. Token-based auth: an ES256 provider JWT from the team's .p8 key,
  reused for 40 minutes (Apple's window is 20–60). Each push is an HTTP/2
  POST to the production or sandbox host the token was issued for.
  """

  @behaviour Palee.Notifications.Ports.NativePushSender

  alias Palee.Infrastructure.Notifications.{NativePushCredentials, NativePushTokenCache}
  alias Palee.Notifications.Domain.NativePushPayload

  @hosts %{
    "production" => "https://api.push.apple.com",
    "sandbox" => "https://api.sandbox.push.apple.com"
  }
  @timeout 10_000

  @impl true
  def configured?, do: match?({:ok, _credentials}, NativePushCredentials.apns())

  @impl true
  def send_push(%{token: token} = device, message) do
    with {:ok, credentials} <- NativePushCredentials.apns(),
         {:ok, provider_token} <- provider_token(credentials) do
      host = Map.get(@hosts, Map.get(device, :apns_environment), @hosts["production"])

      case Req.post(
             host <> "/3/device/" <> URI.encode(token),
             [
               json: NativePushPayload.apns(message),
               headers: NativePushPayload.apns_headers(credentials.topic, provider_token),
               connect_options: [protocols: [:http2]],
               receive_timeout: @timeout,
               retry: false
             ] ++ credentials.req_options
           ) do
        {:ok, %{status: 403, body: %{"reason" => reason} = body}}
        when reason in ["ExpiredProviderToken", "InvalidProviderToken"] ->
          NativePushTokenCache.forget(cache_key(credentials))
          {:error, {:http_error, 403, body}}

        {:ok, %{status: status, body: body}} ->
          NativePushPayload.apns_result(status, decode(body))

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :native_push_not_configured} -> {:error, :push_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp provider_token(credentials) do
    NativePushTokenCache.fetch(cache_key(credentials), 0, fn ->
      claims = %{"iss" => credentials.team_id, "iat" => System.system_time(:second)}

      {_header, jwt} =
        credentials.jwk
        |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => credentials.key_id}, claims)
        |> JOSE.JWS.compact()

      {:ok, jwt, 40 * 60}
    end)
  end

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _not_json -> body
    end
  end

  defp decode(body), do: body

  defp cache_key(credentials), do: {:apns, credentials.team_id, credentials.key_id}
end
