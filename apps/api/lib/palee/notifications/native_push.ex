defmodule Palee.Notifications.NativePush do
  @moduledoc """
  The configured native push senders, one per provider (ADR-171):
  `config :palee, :native_push_senders, %{fcm: …, apns: …}`.
  """

  alias Palee.Notifications.NativePushToken

  @doc "The sender adapter of a provider (`\"fcm\"` / `\"apns\"`)."
  def sender(provider) when provider in ["fcm", "apns"],
    do: Map.fetch!(senders(), String.to_existing_atom(provider))

  @doc "Whether a provider's credentials are configured."
  def configured?(provider) when provider in ["fcm", "apns"], do: sender(provider).configured?()
  def configured?(_provider), do: false

  @doc "The providers that can deliver right now, e.g. `[\"fcm\"]`."
  def configured_providers, do: Enum.filter(NativePushToken.providers(), &configured?/1)

  def send_push(%{provider: provider} = token, message),
    do: sender(provider).send_push(token, message)

  defp senders, do: Application.fetch_env!(:palee, :native_push_senders)
end
