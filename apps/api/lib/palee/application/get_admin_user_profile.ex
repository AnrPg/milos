defmodule Palee.Application.GetAdminUserProfile do
  @moduledoc false

  alias Palee.Application.{AuthorizeProgramming, TenantUserAccess}
  alias Palee.Identity.Domain.AdminProfilePolicy
  alias Palee.Organizations

  def call(user_id, tenant_context, organization_slug \\ nil) do
    case TenantUserAccess.fetch_active_user(tenant_context, user_id) do
      {:ok, user} ->
        roles = TenantUserAccess.tenant_roles(tenant_context, user.id)

        {:ok,
         %{
           user: %{
             identity: %{
               id: user.id,
               nickname: user.nickname,
               role: primary_role(roles, user),
               avatar_url: user.avatar_url,
               joined_at: timestamp(user.inserted_at)
             },
             account_status: "active",
             membership: membership(tenant_context, user.id),
             available_sections: AdminProfilePolicy.sections(roles),
             programming: programming(tenant_context, user.id, roles),
             attention: [],
             operational_links:
               AdminProfilePolicy.operational_links(user, roles, organization_slug)
           }
         }}

      error ->
        error
    end
  end

  # ADR-217: the role the gym knows the person by (its most privileged one);
  # the account-wide role only for someone who holds none there.
  defp primary_role([], user), do: to_string(user.role)

  defp primary_role(roles, _user),
    do: roles |> Palee.Organizations.Domain.MembershipPolicy.primary_role() |> to_string()

  # ADR-225: whether staff may program this client, and through which grant,
  # so the schedule can say so before anyone tries. Nil for non-clients.
  defp programming(tenant_context, user_id, roles) do
    if Enum.any?(roles, &(&1 in [:member, :athlete])) do
      case AuthorizeProgramming.grant_for(tenant_context, user_id) do
        {:ok, grant} -> %{allowed: true, grant: to_string(grant), reason: nil}
        {:error, reason} -> %{allowed: false, grant: nil, reason: to_string(reason)}
      end
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
