defmodule Palee.Organizations.Queries.GetOrganizationBranding do
  @moduledoc "ADR-121: an organization's branding settings for owners/admins and vendors."

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Commands.ReplaceOrganizationLogo
  alias Palee.Organizations.Domain.BrandLogoPolicy
  alias Palee.Organizations.OrganizationStore

  def call(context, organization_id) do
    with {:ok, actor} <- BrandLogoPolicy.authorize(context, organization_id) do
      RepoContext.run(ReplaceOrganizationLogo.repo_scope(context), fn ->
        case OrganizationStore.get_organization_settings(actor.organization_id) do
          nil -> {:error, :not_found}
          settings -> {:ok, settings}
        end
      end)
    end
  end
end
