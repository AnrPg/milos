defmodule Palee.Infrastructure.Devices.GarminHttpClient do
  @moduledoc """
  The Garmin Connect Developer Program over HTTP (Req), ADR-161.

  Runtime config (`config :palee, :garmin`):

      client_id      GARMIN_CLIENT_ID      (required)
      client_secret  GARMIN_CLIENT_SECRET  (required)
      redirect_uri   GARMIN_REDIRECT_URI   (default <public base>/api/integrations/garmin/callback)
      push_token     GARMIN_PUSH_TOKEN     (optional; then the push URL registered at
                                            Garmin must carry ?token=<value>)
      authorize_url, token_url, api_base_url  (overrides, for Garmin's test hosts)

  Garmin does not sign push requests. A push is accepted when its
  `garmin-client-id` header is this app's client id (and the push token
  matches when one is set); every summary must then name a Garmin user with
  a live connection here, and ping callback URLs are fetched only from
  Garmin's API host.
  """

  @behaviour Palee.Devices.Ports.GarminClient

  require Logger

  @authorize_url "https://connect.garmin.com/oauth2Confirm"
  @token_url "https://diauth.garmin.com/di-oauth2-service/oauth/token"
  @api_base_url "https://apis.garmin.com"
  @timeout 15_000

  @impl true
  def configured?, do: match?({:ok, _config}, config())

  @impl true
  def redirect_uri do
    case Keyword.get(raw_config(), :redirect_uri) do
      uri when is_binary(uri) and uri != "" ->
        uri

      _default ->
        Palee.Application.PublicURL.base_url() <> "/api/integrations/garmin/callback"
    end
  end

  @impl true
  def authorize_url(%{state: state, challenge: challenge}) do
    with {:ok, config} <- config() do
      query =
        URI.encode_query(%{
          "response_type" => "code",
          "client_id" => config[:client_id],
          "code_challenge" => challenge,
          "code_challenge_method" => "S256",
          "redirect_uri" => redirect_uri(),
          "state" => state
        })

      {:ok, (config[:authorize_url] || @authorize_url) <> "?" <> query}
    end
  end

  @impl true
  def exchange_code(%{code: code, verifier: verifier}) do
    with {:ok, config} <- config() do
      token_request(config, %{
        "grant_type" => "authorization_code",
        "client_id" => config[:client_id],
        "client_secret" => config[:client_secret],
        "code" => code,
        "code_verifier" => verifier,
        "redirect_uri" => redirect_uri()
      })
    end
  end

  @impl true
  def refresh(refresh_token) do
    with {:ok, config} <- config() do
      token_request(config, %{
        "grant_type" => "refresh_token",
        "client_id" => config[:client_id],
        "client_secret" => config[:client_secret],
        "refresh_token" => refresh_token
      })
    end
  end

  @impl true
  def user_id(access_token) do
    case api(:get, "/wellness-api/rest/user/id", access_token) do
      {:ok, %{"userId" => id}} when is_binary(id) -> {:ok, id}
      {:ok, _body} -> {:error, :garmin_bad_response}
      error -> error
    end
  end

  @impl true
  def permissions(access_token) do
    case api(:get, "/wellness-api/rest/user/permissions", access_token) do
      {:ok, permissions} when is_list(permissions) -> {:ok, Enum.map(permissions, &to_string/1)}
      {:ok, _body} -> {:ok, []}
      error -> error
    end
  end

  @impl true
  def request_backfill(access_token, type, %DateTime{} = from, %DateTime{} = to) do
    path =
      "/wellness-api/rest/backfill/#{type}?" <>
        URI.encode_query(%{
          "summaryStartTimeInSeconds" => DateTime.to_unix(from),
          "summaryEndTimeInSeconds" => DateTime.to_unix(to)
        })

    case api(:get, path, access_token) do
      {:ok, _body} -> :ok
      # Garmin answers 409 to a window it already accepted.
      {:error, {:garmin_http, 409}} -> :ok
      error -> error
    end
  end

  @impl true
  def fetch(access_token, callback_url) do
    with {:ok, config} <- config(),
         :ok <- garmin_url(callback_url, config) do
      case request(:get, callback_url, access_token) do
        {:ok, summaries} when is_list(summaries) ->
          {:ok, summaries}

        {:ok, %{} = body} ->
          {:ok, body |> Map.values() |> Enum.filter(&is_list/1) |> Enum.concat()}

        {:ok, _body} ->
          {:ok, []}

        error ->
          error
      end
    end
  end

  @impl true
  def deregister(access_token) do
    case api(:delete, "/wellness-api/rest/user/registration", access_token) do
      {:ok, _body} -> :ok
      # Already gone at Garmin.
      {:error, {:garmin_http, status}} when status in [401, 404] -> :ok
      error -> error
    end
  end

  @impl true
  def verify_push(%{client_id: client_id, token: token}) do
    with {:ok, config} <- config() do
      expected_token = config[:push_token]

      cond do
        not is_binary(client_id) -> {:error, :invalid_push}
        not Plug.Crypto.secure_compare(client_id, config[:client_id]) -> {:error, :invalid_push}
        expected_token in [nil, ""] -> :ok
        is_binary(token) and Plug.Crypto.secure_compare(token, expected_token) -> :ok
        true -> {:error, :invalid_push}
      end
    end
  end

  defp token_request(config, form) do
    (config[:token_url] || @token_url)
    |> Req.post([form: form, receive_timeout: @timeout, retry: false] ++ req_options())
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => access} = body}} ->
        {:ok,
         %{
           access_token: access,
           refresh_token: body["refresh_token"],
           expires_in: body["expires_in"],
           refresh_token_expires_in: body["refresh_token_expires_in"],
           scopes:
             body |> Map.get("scope", "") |> to_string() |> String.split(~r/[\s,]+/, trim: true)
         }}

      {:ok, %Req.Response{status: status, body: body}} when status in [400, 401] ->
        Logger.warning("garmin token request refused status=#{status}")

        if is_map(body) and body["error"] == "invalid_grant",
          do: {:error, :garmin_invalid_grant},
          else: {:error, {:garmin_http, status}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:garmin_http, status}}

      {:error, reason} ->
        Logger.warning("garmin token request failed #{inspect(reason)}")
        {:error, :garmin_unavailable}
    end
  end

  defp api(method, path, access_token) do
    with {:ok, config} <- config(),
         do: request(method, (config[:api_base_url] || @api_base_url) <> path, access_token)
  end

  defp request(method, url, access_token) do
    [method: method, url: url, receive_timeout: @timeout, retry: false]
    |> Keyword.put(:headers, [{"authorization", "Bearer " <> access_token}])
    |> Keyword.merge(req_options())
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :garmin_unauthorized}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("garmin api answered #{status}")
        {:error, {:garmin_http, status}}

      {:error, reason} ->
        Logger.warning("garmin api failed #{inspect(reason)}")
        {:error, :garmin_unavailable}
    end
  end

  # Ping callbacks are fetched with the person's token, so only from Garmin.
  defp garmin_url(url, config) do
    expected = URI.parse(config[:api_base_url] || @api_base_url)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme == expected.scheme and host == expected.host ->
        :ok

      _other ->
        {:error, :invalid_callback_url}
    end
  end

  defp config do
    config = raw_config()

    if present?(config[:client_id]) and present?(config[:client_secret]),
      do: {:ok, config},
      else: {:error, :garmin_not_configured}
  end

  defp raw_config, do: Application.get_env(:palee, :garmin, [])

  # Tests route requests through `Req.Test`.
  defp req_options, do: Keyword.get(raw_config(), :req_options, [])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
