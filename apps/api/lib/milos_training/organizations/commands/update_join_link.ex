defmodule MilosTraining.Organizations.Commands.UpdateJoinLink do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{JoinLinkPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

  def call(context, params) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      RepoContext.run(context, fn ->
        settings = OrganizationStore.get_organization_settings(context.organization_id)
        current = JoinLinkPolicy.from_settings(settings && settings.settings)

        with {:ok, join_link} <- JoinLinkPolicy.update(current, params),
             {:ok, _settings} <-
               OrganizationStore.put_organization_settings_entry(
                 context.organization_id,
                 JoinLinkPolicy.settings_key(),
                 join_link
               ) do
          {:ok, join_link}
        end
      end)
    end
  end
end
