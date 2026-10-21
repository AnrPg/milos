defmodule Palee.Wallet.Ports.PassUpdater do
  @moduledoc """
  Tells a platform that a pass changed (ADR-155): Apple through APNs (an
  empty push to each registered device; the device then fetches the latest
  pass from the PassKit web service), Google by writing the pass object
  through the Wallet REST API. Not configured → `{:error, :wallet_not_configured}`.

  `update` carries `push_tokens` (Apple) or `content` and `logo_url` (Google).
  Apple answers which tokens are gone (`{:ok, %{gone: [token]}}`) so they
  are forgotten.
  """

  alias Palee.Wallet.Domain.PassContent

  @callback configured?() :: boolean()
  @callback update(%{
              optional(:push_tokens) => [String.t()],
              optional(:content) => PassContent.t(),
              optional(:logo_url) => String.t() | nil
            }) :: {:ok, map()} | {:error, term()}
end
