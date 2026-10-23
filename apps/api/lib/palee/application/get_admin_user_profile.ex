defmodule Palee.Application.GetAdminUserProfile do
  @moduledoc false

  alias Palee.Application.TenantUserAccess
  alias Palee.Identity.Domain.AdminProfilePolicy
  alias Palee.Organizations

  def call(user_id, tenant_context, organization_slug \\ nil) do
    case TenantUserAccess.fetch_active_user(tenant_context, user_id) do
      {:ok, user} ->
        {:ok,
         %{
           user: %{
             identity: %{
               id: user.id,
               nickname: user.nickname,
               role: to_string(user.role),
               avatar_url: user.avatar_url,
               joined_at: timestamp(user.inserted_at)
             },
             account_status: "active",
             membership: membership(tenant_context, user.id),
             available_sections: AdminProfilePolicy.sections(user.role),
             attention: [],
             operational_links: AdminProfilePolicy.operational_links(user, organization_slug)
           }
         }}

      error ->
        error
    end
  end

  # ADR-186: where the person works as staff, for the roles editor.
  defp membership(tenant_context, user_id) do
    case Organizations.membership_summary(tenant_context.organization_id, user_id) do
      %{} = summary ->
        scope = Organizations.stored_location_scope(tenant_context, user_id) || :all
        Map.put(summary, :location_scope, Organizations.location_scope_payload(scope))

      nil ->
        nil
    end
  end

  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil
end
