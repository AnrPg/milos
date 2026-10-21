defmodule MilosTraining.Organizations.Commands.UpdateWorkoutSettings do
  @moduledoc "Changes a gym's workout-authoring defaults (ADR-163); needs `manage_settings`."

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{TenantAuthorization, WorkoutSettingsPolicy}
  alias MilosTraining.Organizations.OrganizationStore

  def call(context, params) do
    with :ok <- TenantAuthorization.authorize_capability(context, :manage_settings) do
      RepoContext.run(context, fn ->
        settings = OrganizationStore.get_organization_settings(context.organization_id)
        current = WorkoutSettingsPolicy.from_settings(settings && settings.settings)

        with {:ok, stored, updated} <- WorkoutSettingsPolicy.update(current, params),
             {:ok, _settings} <-
               OrganizationStore.put_organization_settings_entry(
                 context.organization_id,
                 WorkoutSettingsPolicy.settings_key(),
                 stored
               ) do
          {:ok, updated}
        end
      end)
    end
  end
end
