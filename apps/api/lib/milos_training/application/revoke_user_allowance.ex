defmodule MilosTraining.Application.RevokeUserAllowance do
  @moduledoc "Revokes a personal allowance extension with an auditable compensating entry."

  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Application.TenantUserAccess
  alias MilosTraining.Finance

  def call(tenant_context, user_id, admin_id, grant_id, params) do
    params =
      Map.new(params, fn {key, value} ->
        {if(is_binary(key), do: String.to_existing_atom(key), else: key), value}
      end)

    params = Map.put_new(params, :idempotency_key, "admin-allowance-revoke:#{grant_id}")

    with {:ok, _user} <- TenantUserAccess.fetch_active_user(tenant_context, user_id),
         {:ok, entry} <-
           Finance.revoke_allowance_grant(tenant_context, user_id, admin_id, grant_id, params),
         entitlement when not is_nil(entitlement) <-
           Finance.get_effective_entitlement(tenant_context, user_id) do
      BroadcastUserSync.for_user(user_id, ["finance_entitlement"],
        reason: "allowance_extension_revoked"
      )

      {:ok, %{entry: entry, entitlement: entitlement}}
    else
      nil -> {:error, :finance_profile_missing}
      error -> error
    end
  end
end
