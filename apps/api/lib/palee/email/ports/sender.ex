defmodule Palee.Email.Ports.Sender do
  @moduledoc """
  The port that hands one rendered email to the mail provider (ADR-203).
  An adapter never raises or exits: a provider outage is `{:error, reason}`.
  """

  # `headers` (ADR-212): extra headers such as List-Unsubscribe.
  @type email :: %{
          required(:to) => String.t(),
          required(:subject) => String.t(),
          required(:text) => String.t(),
          required(:html) => String.t(),
          required(:message_id) => String.t(),
          optional(:headers) => %{String.t() => String.t()},
          optional(:attachments) => [attachment()]
        }

  # ADR-265: a file sent with the email (a fiscal document's PDF).
  @type attachment :: %{filename: String.t(), content_type: String.t(), data: binary()}

  @callback deliver(email()) :: {:ok, term()} | {:error, term()}
end
