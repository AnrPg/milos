defmodule MilosTraining.Application.TenantDefaults do
  @moduledoc """
  The defaults every new organization starts with, whichever way it is
  created (ADR-133). Today that is Workouts' default scale levels (ADR-128).

  It is handed to Organizations as the `seed_defaults` of a creation, so it
  runs inside the creation transaction in the new tenant's scope: an error
  here rolls the organization back.
  """

  alias MilosTraining.Workouts

  def call(%{organization_id: organization_id, user_id: _user_id} = scope)
      when is_binary(organization_id) do
    with {:ok, scale_levels} <- Workouts.seed_default_scale_levels(scope) do
      {:ok, %{scale_levels: scale_levels}}
    end
  end
end
