defmodule MilosTraining.Wallet.WalletStore do
  @moduledoc false
  @behaviour MilosTraining.Wallet.Ports.WalletStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :wallet_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def create_pass(context, attrs), do: scoped(context, :create_pass, [attrs])

  @impl true
  def get_active_pass(context, user_id, platform),
    do: scoped(context, :get_active_pass, [user_id, platform])

  @impl true
  def get_pass_by_serial(context, serial), do: scoped(context, :get_pass_by_serial, [serial])

  @impl true
  def get_pass(context, id), do: scoped(context, :get_pass, [id])

  @impl true
  def revoke_pass(context, id, at), do: scoped(context, :revoke_pass, [id, at])

  @impl true
  def touch_user_passes(context, user_id, at),
    do: scoped(context, :touch_user_passes, [user_id, at])

  @impl true
  def list_user_passes(context, user_id), do: scoped(context, :list_user_passes, [user_id])

  @impl true
  def register_device(context, pass_id, device, push_token),
    do: scoped(context, :register_device, [pass_id, device, push_token])

  @impl true
  def unregister_device(context, pass_id, device),
    do: scoped(context, :unregister_device, [pass_id, device])

  @impl true
  def push_tokens(context, pass_id), do: scoped(context, :push_tokens, [pass_id])

  @impl true
  def forget_push_token(context, token), do: scoped(context, :forget_push_token, [token])

  # Before a tenant is known: narrow SECURITY DEFINER lookups.
  @impl true
  def pass_organization(serial), do: adapter().pass_organization(serial)

  @impl true
  def device_serials(device, since), do: adapter().device_serials(device, since)
end
