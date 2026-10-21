defmodule MilosTraining.Notifications.Ports.NativePushSender do
  @moduledoc """
  Delivers one push to one store app install (ADR-171). One adapter per
  provider (`fcm`, `apns`); credentials come from runtime config and without
  them `configured?/0` is false and nothing is sent.

  `send_push/2` answers `:ok`, `{:error, :expired}` when the provider says the
  token is gone (the token is then deleted), or another `{:error, reason}`
  (`{:http_error, status, body}` for provider refusals, so the delivery
  outcome classification of web push applies unchanged).
  """

  @callback configured?() :: boolean()
  @callback send_push(token :: map(), message :: map()) :: :ok | {:error, term()}
end
