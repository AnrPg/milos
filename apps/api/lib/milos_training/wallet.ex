defmodule MilosTraining.Wallet do
  @moduledoc """
  Wallet context (ADR-155): members' Apple and Google Wallet cards per box,
  the Apple devices registered for their updates, and the platform ports
  that build and update passes (configured from runtime credentials).
  """

  alias MilosTraining.Wallet.Domain.TenantDataPolicy
  alias MilosTraining.Wallet.WalletStore

  def platforms, do: MilosTraining.Wallet.WalletPass.platforms()

  def create_pass(context, attrs), do: WalletStore.create_pass(context, attrs)

  def get_active_pass(context, user_id, platform),
    do: WalletStore.get_active_pass(context, user_id, platform)

  def get_pass_by_serial(context, serial), do: WalletStore.get_pass_by_serial(context, serial)
  def get_pass(context, id), do: WalletStore.get_pass(context, id)

  @doc "Revokes the active cards that carry any of these member codes; returns them."
  def revoke_code_passes(_context, [], _at), do: []

  def revoke_code_passes(context, code_ids, at),
    do: WalletStore.revoke_code_passes(context, code_ids, at)

  def revoke_pass(context, id, at), do: WalletStore.revoke_pass(context, id, at)

  def touch_user_passes(context, user_id, at),
    do: WalletStore.touch_user_passes(context, user_id, at)

  def list_user_passes(%{user_id: user_id} = context),
    do: WalletStore.list_user_passes(context, user_id)

  def register_device(context, pass_id, device, push_token),
    do: WalletStore.register_device(context, pass_id, device, push_token)

  def unregister_device(context, pass_id, device),
    do: WalletStore.unregister_device(context, pass_id, device)

  def push_tokens(context, pass_id), do: WalletStore.push_tokens(context, pass_id)
  def forget_push_token(context, token), do: WalletStore.forget_push_token(context, token)
  def pass_organization(serial), do: WalletStore.pass_organization(serial)
  def device_serials(device, since), do: WalletStore.device_serials(device, since)

  @doc "The pass builder of a platform (`:apple` / `:google`)."
  def builder(platform), do: adapter(:wallet_pass_builders, platform)

  @doc "The pass updater of a platform."
  def updater(platform), do: adapter(:wallet_pass_updaters, platform)

  def image_source, do: Application.fetch_env!(:milos_training, :wallet_image_source)

  @doc "Whether a platform's credentials are configured."
  def configured?(platform), do: builder(platform).configured?()

  @doc "Apple pass settings the PassKit web service checks (pass type id), or nil."
  def apple_pass_type_identifier do
    :milos_training |> Application.get_env(:wallet, []) |> get_in([:apple, :pass_type_identifier])
  end

  defp adapter(key, platform) when is_binary(platform),
    do: adapter(key, String.to_existing_atom(platform))

  defp adapter(key, platform) when is_atom(platform),
    do: :milos_training |> Application.fetch_env!(key) |> Map.fetch!(platform)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
