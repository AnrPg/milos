defmodule Palee.Organizations.Commands.SetCoachScope do
  @moduledoc """
  Makes a coach a head coach (`:all`) or returns them to their own clients
  (`:own`) (ADR-100). Only owners and admins decide this.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.TenantAuthorization
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
         true <- :coach in membership.roles || {:error, :not_a_coach} do
      OrganizationStore.update_membership_settings(
        context.organization_id,
        membership.id,
        %{coach_scope: scope}
      )
    end
  end

  defp normalize(scope) when scope in [:own, :all], do: {:ok, scope}
  defp normalize("own"), do: {:ok, :own}
  defp normalize("all"), do: {:ok, :all}
  defp normalize(_scope), do: {:error, [coach_scope: "is invalid"]}
end
