defmodule MilosTraining.Devices.GarminClient do
  @moduledoc "Dispatches the Garmin client port to the configured adapter (ADR-161)."

  @behaviour MilosTraining.Devices.Ports.GarminClient

  @impl true
  def configured?, do: adapter().configured?()
  @impl true
  def redirect_uri, do: adapter().redirect_uri()
  @impl true
  def authorize_url(params), do: adapter().authorize_url(params)
  @impl true
  def exchange_code(params), do: adapter().exchange_code(params)
  @impl true
  def refresh(refresh_token), do: adapter().refresh(refresh_token)
  @impl true
  def user_id(access_token), do: adapter().user_id(access_token)
  @impl true
  def permissions(access_token), do: adapter().permissions(access_token)
  @impl true
  def request_backfill(access_token, type, from, to),
    do: adapter().request_backfill(access_token, type, from, to)

  @impl true
  def fetch(access_token, callback_url), do: adapter().fetch(access_token, callback_url)
  @impl true
  def deregister(access_token), do: adapter().deregister(access_token)
  @impl true
  def verify_push(params), do: adapter().verify_push(params)

  defp adapter do
    Application.get_env(
      :milos_training,
      :garmin_client,
      MilosTraining.Infrastructure.Devices.GarminHttpClient
    )
  end
end
