defmodule MilosTraining.Organizations.Commands.SetRoleGrants do
  @moduledoc """
  What a gym unlocks for a role beyond its defaults, e.g. invoices or
  campaigns for front desk (ADR-099). Owners and admins decide.
  """

  alias MilosTraining.Organizations.Domain.{AccessPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

  def get(context) do
    with :ok <- TenantAuthorization.authorize_capability(context, :manage_settings) do
      {:ok, current(context.organization_id)}
    end
  end

  def call(context, role, capabilities) when is_list(capabilities) do
    with :ok <- TenantAuthorization.authorize_capability(context, :manage_settings),
         {:ok, role} <- grantable_role(role) do
      unlocked =
        role
        |> AccessPolicy.unlocked(%{to_string(role) => capabilities})
        |> Map.keys()
        |> Enum.map(&to_string/1)
        |> Enum.sort()

      grants = Map.put(current(context.organization_id), to_string(role), unlocked)

      with {:ok, _settings} <-
             OrganizationStore.put_organization_setting(
               context.organization_id,
               "role_grants",
               grants
             ) do
        {:ok, grants}
      end
    end
  end

  def call(_context, _role, _capabilities), do: {:error, [capabilities: "must be a list"]}

  @doc "Every role a gym may unlock capabilities for, with the choices."
  def grantable do
    Map.new(AccessPolicy.grantable(), fn {role, capabilities} ->
      {to_string(role), Enum.map(capabilities, &to_string/1)}
    end)
  end

  defp current(organization_id) do
    case OrganizationStore.get_organization_settings(organization_id) do
      %{settings: %{"role_grants" => grants}} when is_map(grants) -> grants
      _none -> %{}
    end
  end

  defp grantable_role(role) do
    case Enum.find(Map.keys(AccessPolicy.grantable()), &(to_string(&1) == to_string(role))) do
      nil -> {:error, :invalid_role}
      role -> {:ok, role}
    end
  end
end
