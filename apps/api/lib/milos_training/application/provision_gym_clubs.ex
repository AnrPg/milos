defmodule MilosTraining.Application.ProvisionGymClubs do
  @moduledoc """
  Backfill and self-heal for ADR-138: every active gym has its club and the
  club's built-in channels. New gyms get them inside provisioning
  (`TenantDefaults`); this covers gyms created before the Community context
  and any built-in channel added later. Idempotent.
  """

  alias MilosTraining.{Community, Organizations}

  def call do
    Organizations.list_active_organizations_for_system()
    |> Enum.reduce_while(:ok, fn %{organization: organization}, :ok ->
      case Community.provision_gym_club(%{organization_id: organization.id}) do
        {:ok, _club} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {organization.id, reason}}}
      end
    end)
  end
end
