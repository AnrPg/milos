defmodule Palee.Email.Ports.Sender do
  @moduledoc """
  The port that hands one rendered email to the mail provider (ADR-203).
  An adapter never raises or exits: a provider outage is `{:error, reason}`.
  """

  @type email :: %{
          to: String.t(),
          subject: String.t(),
          text: String.t(),
          html: String.t(),
          message_id: String.t()
        }

  @callback deliver(email()) :: {:ok, term()} | {:error, term()}
end
