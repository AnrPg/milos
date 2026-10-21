defmodule MilosTraining.Infrastructure.Notifications.FcmSender do
  @moduledoc """
  FCM HTTP v1 adapter of `Notifications.Ports.NativePushSender` (ADR-171),
  for the Android app. Authenticates with the Firebase service account (JWT
  bearer grant for the `firebase.messaging` scope) and posts one message per
  token to `projects/<id>/messages:send`.
  """

  @behaviour MilosTraining.Notifications.Ports.NativePushSender

  alias MilosTraining.Infrastructure.Notifications.{NativePushCredentials, NativePushTokenCache}
  alias MilosTraining.Notifications.Domain.NativePushPayload

  @scope "https://www.googleapis.com/auth/firebase.messaging"
  @send_url "https://fcm.googleapis.com/v1/projects/"
  @timeout 10_000

  @impl true
  def configured?, do: match?({:ok, _credentials}, NativePushCredentials.fcm())

  @impl true
  def send_push(%{token: token}, message) do
    with {:ok, credentials} <- NativePushCredentials.fcm(),
         {:ok, access_token} <- access_token(credentials) do
      url = @send_url <> URI.encode(credentials.project_id) <> "/messages:send"

      case Req.post(
             url,
             [
               json: NativePushPayload.fcm(token, message),
               headers: [{"authorization", "Bearer " <> access_token}],
               receive_timeout: @timeout,
               retry: false
             ] ++ credentials.req_options
           ) do
        {:ok, %{status: 401}} ->
          NativePushTokenCache.forget(cache_key(credentials))
          {:error, {:http_error, 401, :unauthorized}}

        {:ok, %{status: status, body: body}} ->
          NativePushPayload.fcm_result(status, body)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :native_push_not_configured} -> {:error, :push_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp access_token(credentials) do
    NativePushTokenCache.fetch(cache_key(credentials), 300, fn ->
      now = System.system_time(:second)

      claims = %{
        "iss" => credentials.client_email,
        "scope" => @scope,
        "aud" => credentials.token_uri,
        "iat" => now,
        "exp" => now + 3600
      }

      {_header, assertion} =
        credentials.jwk |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()

      case Req.post(
             credentials.token_uri,
             [
               form: [
                 grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
                 assertion: assertion
               ],
               receive_timeout: @timeout,
               retry: false
             ] ++ credentials.req_options
           ) do
        {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
          {:ok, token, Map.get(body, "expires_in", 3600)}

        {:ok, %{status: status}} ->
          {:error, {:fcm_oauth, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp cache_key(credentials), do: {:fcm, credentials.client_email}
end
