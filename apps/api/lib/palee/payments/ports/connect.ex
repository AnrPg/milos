defmodule Palee.Payments.Ports.Connect do
  @moduledoc """
  One-button connection of a business's provider account (ADR-261): Palee,
  registered once with the provider as a platform, sends the owner to the
  provider's own page, where they sign in or open a merchant account and
  allow Palee to take payments for them. Palee keeps only the connected
  account's id; no secret of the business ever passes through Palee.

  `environment` is "test" or "live" and picks the platform credentials.
  """

  @doc "Whether Palee is registered with the provider for this environment."
  @callback available?(environment :: String.t()) :: boolean()

  @doc """
  The provider page to send the owner to. `request`: state (signed by
  Palee, returned untouched), redirect_uri, and hints to prefill (email,
  business_name, country).
  """
  @callback authorize_url(environment :: String.t(), request :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Finishes the connection from the provider's redirect parameters."
  @callback complete(environment :: String.t(), params :: map()) ::
              {:ok, %{connected_account: String.t()}}
              | {:error, :access_denied | :invalid_grant | term()}

  @doc "Removes Palee's access to the connected account at the provider."
  @callback disconnect(environment :: String.t(), connected_account :: String.t()) ::
              :ok | {:error, term()}
end
