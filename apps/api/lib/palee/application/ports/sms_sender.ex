defmodule Palee.Application.Ports.SmsSender do
  @moduledoc """
  Sends one text message (ADR-280 §3). `to` is an E.164 number, `body` the
  text, `tag` a short label for the provider's reports (no personal data).
  Configured as `config :palee, :sms_sender`. An adapter that cannot send
  answers `{:error, :sms_unavailable}`; it never raises.
  """

  @type message :: %{to: String.t(), body: String.t(), tag: String.t()}

  @callback deliver(message()) :: :ok | {:error, term()}
end
