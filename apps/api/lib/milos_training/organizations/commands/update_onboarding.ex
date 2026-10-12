defmodule MilosTraining.Organizations.Commands.UpdateOnboarding do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{OnboardingChecklist, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

  def call(context, params, now) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      RepoContext.run(context, fn ->
        settings = OrganizationStore.get_organization_settings(context.organization_id)
        current = OnboardingChecklist.from_settings(settings && settings.settings)

        with {:ok, state} <- OnboardingChecklist.apply_action(current, params, now),
             {:ok, _settings} <-
               OrganizationStore.put_organization_settings_entry(
                 context.organization_id,
                 OnboardingChecklist.settings_key(),
                 state
               ) do
          {:ok, state}
        end
      end)
    end
  end
end
