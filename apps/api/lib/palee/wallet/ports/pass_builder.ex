defmodule Palee.Wallet.Ports.PassBuilder do
  @moduledoc """
  Builds a Wallet pass from `PassContent` (ADR-155, decision 5). The Apple
  adapter returns a signed `.pkpass`; the Google adapter a «Save to Google
  Wallet» link. Credentials come from runtime config; without them
  `configured?/0` is false and `build/2` returns `{:error, :wallet_not_configured}`.

  `opts`: `authentication_token` and `web_service_url` (Apple), `images`
  (`%{"icon.png" => bytes, ...}`, Apple), `logo_url` (Google), `now`.
  """

  alias Palee.Wallet.Domain.PassContent

  @type built :: %{kind: :pkpass, body: binary()} | %{kind: :save_link, url: String.t()}

  @callback configured?() :: boolean()
  @callback build(PassContent.t(), map()) :: {:ok, built()} | {:error, term()}
end
