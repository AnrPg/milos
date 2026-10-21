defmodule Palee.Organizations.Queries.ListActiveOrganizationsForSystem do
  @moduledoc """
  TD-092 / ADR-131: the organizations a per-tenant cron job visits.

  A job runs with no session scope, and the organizations policies admit only
  vendors, members, invitation redemption or a session already scoped to one
  organization, so the plain `list_organizations/0` returned nothing under the
  production runtime role. The ids come from the narrow SECURITY DEFINER
  `palee_active_organization_ids()`; each organization and its settings are
  then read inside that organization's own scope (scoped self-read policies).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore

  def call do
    Enum.flat_map(OrganizationStore.list_active_organization_ids(), &load/1)
  end

  defp load(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      case OrganizationStore.get_organization_by_id(organization_id) do
        %{status: :active} = organization ->
          [
            %{
              organization: organization,
              settings: OrganizationStore.get_organization_settings(organization_id)
            }
          ]

        _missing_or_inactive ->
          []
      end
    end)
  end
end
