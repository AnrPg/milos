defmodule Palee.Infrastructure.Wallet.GoogleWalletUpdater do
  @moduledoc """
  Google adapter of `Wallet.Ports.PassUpdater` (ADR-155): writes the member's
  generic object through the Google Wallet REST API (PUT, or POST when it was
  never saved), with an OAuth access token from the service account (JWT
  bearer grant).
  """

  @behaviour Palee.Wallet.Ports.PassUpdater

  alias Palee.Infrastructure.Wallet.{Credentials, GooglePassBuilder}
  alias Palee.Wallet.Domain.GooglePass

  @token_url "https://oauth2.googleapis.com/token"
  @objects_url "https://walletobjects.googleapis.com/walletobjects/v1/genericObject"
  @scope "https://www.googleapis.com/auth/wallet_object.issuer"

  @impl true
  def configured?, do: match?({:ok, _credentials}, Credentials.google())

  @impl true
  def update(%{content: content} = update) do
    with {:ok, credentials} <- Credentials.google(),
         {:ok, token} <- access_token(credentials) do
      object = GooglePass.generic_object(content, credentials.issuer_id, update[:logo_url])
      auth = [{"authorization", "Bearer " <> token}]

      case Req.put("#{@objects_url}/#{URI.encode(object["id"])}",
             json: object,
             headers: auth,
             retry: false
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, %{object_id: object["id"]}}

        {:ok, %{status: 404}} ->
          insert(object, auth)

        {:ok, %{status: status, body: body}} ->
          {:error, {:google_wallet, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def update(_update), do: {:ok, %{}}

  defp insert(object, auth) do
    case Req.post(@objects_url, json: object, headers: auth, retry: false) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, %{object_id: object["id"]}}
      {:ok, %{status: status, body: body}} -> {:error, {:google_wallet, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp access_token(credentials) do
    now = System.system_time(:second)

    assertion =
      GooglePassBuilder.sign(
        %{
          "iss" => credentials.service_account_email,
          "scope" => @scope,
          "aud" => @token_url,
          "iat" => now,
          "exp" => now + 3600
        },
        credentials
      )

    case Req.post(@token_url,
           form: [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion],
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, %{status: status, body: body}} -> {:error, {:google_oauth, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
