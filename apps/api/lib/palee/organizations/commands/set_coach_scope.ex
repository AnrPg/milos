defmodule Palee.Organizations.Commands.SetCoachScope do
  @moduledoc """
  Makes a coach a head coach (`:all`) or returns them to their own clients
  (`:own`) (ADR-100). Only owners and admins decide this, for coaches ranked
  below them or for themselves (ADR-219).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{MembershipPolicy, TenantAuthorization}
  alias Palee.Organizations.OrganizationStore

  def call(context, user_id, scope) when is_binary(user_id) do
    with :ok <- TenantAuthorization.authorize_capability(context, :set_head_coach),
         {:ok, scope} <- normalize(scope) do
      RepoContext.run(context, fn -> change_scope(context, user_id, scope) end)
    end
  end

  def call(_context, _user_id, _scope), do: {:error, :not_found}

  defp change_scope(context, user_id, scope) do
    with %{} = membership <-
           OrganizationStore.get_membership(context.organization_id, user_id) ||
             {:error, :not_found},
         true <- :coach in membership.roles || {:error, :not_a_coach},
         :ok <- authorize_hierarchy(context, membership),
         # ADR-186: only for a coach of the granter's own branches.
         :ok <-
           Palee.Organizations.Commands.SetMembershipLocationScope.authorize_manage(
             context,
             membership,
             membership.roles
           ) do
      OrganizationStore.update_membership_settings(
        context.organization_id,
        membership.id,
        %{coach_scope: scope}
      )
    end
  end

  defp authorize_hierarchy(context, membership) do
    if membership.user_id == context.user_id or
         MembershipPolicy.can_manage_member?(TenantAuthorization.roles(context), membership.roles),
       do: :ok,
       else: {:error, :role_ceiling_exceeded}
  end

  defp normalize(scope) when scope in [:own, :all], do: {:ok, scope}
  defp normalize("own"), do: {:ok, :own}
  defp normalize("all"), do: {:ok, :all}
  defp normalize(_scope), do: {:error, [coach_scope: "is invalid"]}
end
