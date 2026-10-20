defmodule MilosTraining.Infrastructure.Wallet.ApnsPassUpdater do
  @moduledoc """
  Apple adapter of `Wallet.Ports.PassUpdater` (ADR-155): an empty push per
  registered device over HTTP/2 to APNs, authenticated with the pass type
  certificate (TLS client certificate) and addressed to the pass type id.
  The device then asks the PassKit web service for the latest pass. Tokens
  APNs says are gone (410, BadDeviceToken) are reported so they are dropped.
  """

  @behaviour MilosTraining.Wallet.Ports.PassUpdater

  require Logger

  alias MilosTraining.Infrastructure.Wallet.Credentials

  @impl true
  def configured?, do: match?({:ok, _credentials}, Credentials.apple())

  @impl true
  def update(%{push_tokens: tokens}) when is_list(tokens) do
    with {:ok, credentials} <- Credentials.apple() do
      gone =
        Enum.filter(tokens, fn token -> push(credentials, token) == :gone end)

      {:ok, %{sent: length(tokens) - length(gone), gone: gone}}
    end
  end

  def update(_update), do: {:ok, %{sent: 0, gone: []}}

  defp push(credentials, token) do
    case Req.post(credentials.apns_host <> "/3/device/" <> token,
           json: %{},
           headers: [{"apns-topic", credentials.pass_type_identifier}],
           retry: false,
           connect_options: [
             protocols: [:http2],
             transport_opts: [
               cert: credentials.certificate,
               key: key(credentials.private_key)
             ]
           ]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} when status in [400, 410] ->
        if status == 410 or match?(%{"reason" => "BadDeviceToken"}, body),
          do: :gone,
          else: log(status, body)

      {:ok, %{status: status, body: body}} ->
        log(status, body)

      {:error, reason} ->
        Logger.warning("apns_pass_push_failed #{inspect(reason)}")
        :error
    end
  end

  defp log(status, body) do
    Logger.warning("apns_pass_push_rejected status=#{status} body=#{inspect(body)}")
    :error
  end

  defp key({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} = key),
    do: {:RSAPrivateKey, :public_key.der_encode(:RSAPrivateKey, key)}

  defp key(key) when elem(key, 0) == :ECPrivateKey,
    do: {:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, key)}
end
