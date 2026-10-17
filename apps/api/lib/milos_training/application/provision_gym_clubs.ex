defmodule MilosTraining.Application.ProvisionGymClubs do
  @moduledoc """
  Backfill and self-heal for ADR-138: every active gym has its club and the
  club's built-in channels. New gyms get them inside provisioning
  (`TenantDefaults`); this covers gyms created before the Community context
  and any built-in channel added later, then syncs each gym's class-slot
  groups (D7). Idempotent.
  """

  alias MilosTraining.Application.SyncClassGroups
  alias MilosTraining.{Community, Organizations}

  def call do
    Organizations.list_active_organizations_for_system()
    |> Enum.reduce_while(:ok, fn %{organization: organization}, :ok ->
      context = %{organization_id: organization.id}

      with {:ok, _club} <- Community.provision_gym_club(context),
           {:ok, _synced} <- SyncClassGroups.call(context) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {organization.id, reason}}}
      end
    end)
  end
end
