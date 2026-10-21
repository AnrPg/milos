defmodule Palee.Organizations.Queries.GetJoinLink do
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{JoinLinkPolicy, TenantAuthorization}
  alias Palee.Organizations.OrganizationStore

  def call(context) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      settings =
        RepoContext.run(context, fn ->
          OrganizationStore.get_organization_settings(context.organization_id)
        end)

      {:ok, JoinLinkPolicy.from_settings(settings && settings.settings)}
    end
  end
end
