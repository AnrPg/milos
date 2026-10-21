defmodule MilosTraining.FakeGarminClient do
  @moduledoc """
  Test stand-in for Garmin (ADR-161). Off until a test calls `configure/1`;
  then it answers like Garmin does, with the overrides given, and reports
  every call to the calling process as `{:garmin, call, args}`.

      FakeGarminClient.configure(user_id: "garmin-1", exchange: {:error, :garmin_unavailable})
  """

  @behaviour MilosTraining.Devices.Ports.GarminClient

  @client_id "test-garmin-client"
  @key :fake_garmin

  def client_id, do: @client_id

  def configure(overrides \\ []),
    do: Application.put_env(:milos_training, @key, Map.new([{:configured, true} | overrides]))

  def reset, do: Application.delete_env(:milos_training, @key)

  defp opt(key, default),
    do: :milos_training |> Application.get_env(@key, %{}) |> Map.get(key, default)

  defp report(call, args), do: send(self(), {:garmin, call, args})

  @impl true
  def configured?, do: opt(:configured, false)

  @impl true
  def redirect_uri, do: "http://localhost:4000/api/integrations/garmin/callback"

  @impl true
  def authorize_url(%{state: state, challenge: challenge} = params) do
    report(:authorize_url, params)

    if configured?(),
      do:
        {:ok,
         "https://connect.garmin.test/oauth2Confirm?" <>
           URI.encode_query(%{"state" => state, "code_challenge" => challenge})},
      else: {:error, :garmin_not_configured}
  end

  @impl true
  def exchange_code(params) do
    report(:exchange_code, params)

    opt(
      :exchange,
      {:ok,
       %{
         access_token: "access-1",
         refresh_token: "refresh-1",
         expires_in: 86_400,
         refresh_token_expires_in: 7_776_000,
         scopes: ["ACTIVITY_EXPORT", "HEALTH_EXPORT"]
       }}
    )
  end

  @impl true
  def refresh(refresh_token) do
    report(:refresh, refresh_token)

    opt(
      :refresh,
      {:ok,
       %{
         access_token: "access-refreshed",
         refresh_token: "refresh-2",
         expires_in: 86_400,
         refresh_token_expires_in: 7_776_000,
         scopes: []
       }}
    )
  end

  @impl true
  def user_id(token) do
    report(:user_id, token)
    {:ok, opt(:user_id, "garmin-user-1")}
  end

  @impl true
  def permissions(token) do
    report(:permissions, token)
    {:ok, opt(:permissions, ["ACTIVITY_EXPORT", "HEALTH_EXPORT"])}
  end

  @impl true
  def request_backfill(token, type, from, to) do
    report(:request_backfill, {token, type, from, to})
    opt(:backfill, :ok)
  end

  @impl true
  def fetch(token, url) do
    report(:fetch, {token, url})

    if String.starts_with?(url, "https://apis.garmin.com/"),
      do: opt(:fetch, {:ok, []}),
      else: {:error, :invalid_callback_url}
  end

  @impl true
  def deregister(token) do
    report(:deregister, token)
    opt(:deregister, :ok)
  end

  @impl true
  def verify_push(%{client_id: client_id}) do
    cond do
      not configured?() -> {:error, :garmin_not_configured}
      client_id == @client_id -> :ok
      true -> {:error, :invalid_push}
    end
  end
end
