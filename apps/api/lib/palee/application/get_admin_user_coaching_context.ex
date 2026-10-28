defmodule Palee.Application.GetAdminUserCoachingContext do
  @moduledoc false

  alias Palee.Application.{GetCoachingAthleteDrillDown, TenantUserAccess}
  alias Palee.Identity
  alias Palee.Identity.Domain.AdminProfilePolicy

  def call(%{organization_id: organization_id} = context, user_id, params)
      when is_binary(organization_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found} do
      if AdminProfilePolicy.coaching_available?(TenantUserAccess.tenant_roles(context, user.id)) do
        with {:ok, %{drill_down: drill_down}} <-
               GetCoachingAthleteDrillDown.call(context, user_id, params) do
          {:ok, %{user_id: user_id, available: true, drill_down: drill_down}}
        end
      else
        {:ok, %{user_id: user_id, available: false, drill_down: nil}}
      end
    end
  end

  def call(_context, _user_id, _params), do: {:error, :organization_context_required}
end
