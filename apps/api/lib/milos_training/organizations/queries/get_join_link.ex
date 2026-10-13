defmodule MilosTraining.Organizations.Queries.GetJoinLink do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{JoinLinkPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

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
