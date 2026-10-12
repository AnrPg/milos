defmodule MilosTraining.Organizations.Queries.GetOrganizationBranding do
  @moduledoc "ADR-103: an organization's branding settings for owners/admins and vendors."

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Commands.ReplaceOrganizationLogo
  alias MilosTraining.Organizations.Domain.BrandLogoPolicy
  alias MilosTraining.Organizations.OrganizationStore

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
