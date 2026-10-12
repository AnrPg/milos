defmodule MilosTraining.Application.ProvisionOrganization do
  @moduledoc """
  Provisions an organization (Organizations) and gives it the default scale
  levels (Workouts, ADR-128), running the seed inside the new tenant's scope.

  The two writes are separate transactions in separate contexts. Seeding is
  idempotent and a fresh organization's table is empty, so the only failure
  mode is a database outage; the error is returned rather than swallowed and
  the tenant admin can still configure levels via the scale-levels endpoint.
  """

  alias MilosTraining.{Organizations, Workouts}

  def call(platform_context, params) do
    with {:ok, %{organization: organization} = result} <-
           Organizations.provision_organization(platform_context, params),
         {:ok, _levels} <-
           Workouts.seed_default_scale_levels(%{
             organization_id: organization.id,
             user_id: platform_context.user_id
           }) do
      {:ok, result}
    end
  end
end
