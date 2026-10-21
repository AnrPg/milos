defmodule Palee.Wallet.Ports.WalletStore do
  @moduledoc "Persistence port of the Wallet context (ADR-155)."

  @type context :: %{optional(:organization_id) => binary(), optional(:user_id) => binary()}

  @callback create_pass(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_active_pass(context(), binary(), String.t()) :: map() | nil
  @callback get_pass_by_serial(context(), String.t()) :: map() | nil
  @callback get_pass(context(), binary()) :: map() | nil
  @callback revoke_pass(context(), binary(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  @callback revoke_code_passes(context(), [binary()], DateTime.t()) :: [map()]
  @callback touch_user_passes(context(), binary(), DateTime.t()) :: [map()]
  @doc "The person's cards at every box (the owner-read policy)."
  @callback list_user_passes(context(), binary()) :: [map()]
  @callback register_device(context(), binary(), String.t(), String.t()) ::
              {:ok, :created | :existing} | {:error, term()}
  @callback unregister_device(context(), binary(), String.t()) :: :ok
  @callback push_tokens(context(), binary()) :: [String.t()]
  @callback forget_push_token(context(), String.t()) :: :ok
  @doc "Which box a serial belongs to, before any tenant is known (definer lookup)."
  @callback pass_organization(String.t()) :: binary() | nil
  @doc "The serials registered by a device and changed since `since` (definer lookup)."
  @callback device_serials(String.t(), DateTime.t() | nil) :: [{String.t(), DateTime.t()}]
end
