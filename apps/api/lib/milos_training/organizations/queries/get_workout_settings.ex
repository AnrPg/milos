defmodule MilosTraining.Organizations.Queries.GetWorkoutSettings do
  @moduledoc """
  A gym's workout-authoring defaults (ADR-163). Readable by any staff
  member: the workout editor needs the goals toggle's starting value.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.WorkoutSettingsPolicy
  alias MilosTraining.Organizations.OrganizationStore

  def call(%{organization_id: organization_id} = context) when is_binary(organization_id) do
    settings =
      RepoContext.run(context, fn ->
        OrganizationStore.get_organization_settings(organization_id)
      end)

    WorkoutSettingsPolicy.from_settings(settings && settings.settings)
  end

  def call(_context), do: WorkoutSettingsPolicy.defaults()
end
