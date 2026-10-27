defmodule Palee.Identity.Ports.PasswordResetQueue do
  @moduledoc """
  ADR-206: hands a "forgot password" request to a background job, so the
  answer to the person takes the same time whether the account exists, gets
  an email or reaches the handlers.

  `args` carries the typed identifier, `cant_access_email`, the page's
  `locale` and the client's `requester_key` (an HMAC of its IP, never the
  IP itself).
  """

  @callback submit(map()) :: :ok | {:error, term()}
end
