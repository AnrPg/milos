defmodule Palee.Application.Sms do
  @moduledoc "The configured `Ports.SmsSender` (ADR-280 §3)."

  @behaviour Palee.Application.Ports.SmsSender

  require Logger

  @impl true
  def deliver(%{to: _to, body: _body, tag: _tag} = message) do
    case impl().deliver(message) do
      :ok ->
        :ok

      {:error, :sms_unavailable} ->
        {:error, :sms_unavailable}

      {:error, reason} ->
        Logger.warning("sms_delivery_failed tag=#{message.tag} reason=#{inspect(reason)}")
        {:error, :sms_unavailable}
    end
  end

  defp impl, do: Application.fetch_env!(:palee, :sms_sender)
end
