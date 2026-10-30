defmodule Palee.Infrastructure.Sms.LogSmsSender do
  @moduledoc """
  Development SMS adapter (ADR-280 §3): logs the masked number and the text
  (which carries the code) instead of sending, so the phone step works
  locally without a provider.
  """

  @behaviour Palee.Application.Ports.SmsSender

  require Logger

  @impl true
  def deliver(%{to: to, body: body, tag: tag}) do
    Logger.info("sms tag=#{tag} to=#{mask(to)} body=#{inspect(body)}")
    :ok
  end

  defp mask(to) when is_binary(to) and byte_size(to) > 5,
    do:
      String.slice(to, 0, 3) <>
        String.duplicate("•", byte_size(to) - 6) <> String.slice(to, -3, 3)

  defp mask(_to), do: "•••"
end
