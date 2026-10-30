defmodule Palee.Infrastructure.Sms.BrevoSmsSender do
  @moduledoc """
  Brevo transactional SMS (ADR-280 §3): `POST /v3/transactionalSMS/sms`
  with the `api-key` header (`BREVO_API_KEY`), the sender name
  (`SMS_SENDER`, default `Palee`) and `type: transactional`. Brevo SMS needs
  prepaid credits; any failure answers `{:error, reason}` and never raises.

  Configured by `config :palee, Palee.Infrastructure.Sms.BrevoSmsSender,
  api_key: ..., sender: ..., base_url: ...`.
  """

  @behaviour Palee.Application.Ports.SmsSender

  @default_base_url "https://api.brevo.com"
  @path "/v3/transactionalSMS/sms"

  @impl true
  def deliver(%{to: to, body: body, tag: tag}) do
    config = Application.get_env(:palee, __MODULE__, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" -> post(config, key, to, body, tag)
      _missing -> {:error, :sms_unavailable}
    end
  end

  defp post(config, key, to, body, tag) do
    payload = %{
      sender: Keyword.get(config, :sender) || "Palee",
      # Brevo takes the number with its country code, without the plus.
      recipient: String.trim_leading(to, "+"),
      content: body,
      type: "transactional",
      tag: tag
    }

    case Req.post((Keyword.get(config, :base_url) || @default_base_url) <> @path,
           json: payload,
           headers: [{"api-key", key}, {"accept", "application/json"}],
           receive_timeout: 10_000,
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:brevo_sms, status}}
      {:error, reason} -> {:error, {:brevo_sms, reason}}
    end
  rescue
    error -> {:error, {:brevo_sms, Exception.message(error)}}
  end
end
