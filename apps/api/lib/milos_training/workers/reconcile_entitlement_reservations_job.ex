defmodule MilosTraining.Workers.ReconcileEntitlementReservationsJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.Organizations
  alias MilosTraining.Finance

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    Organizations.list_active_organizations_for_system()
    |> Enum.reduce_while(:ok, fn %{organization: organization}, :ok ->
      case Finance.release_stale_entitlement_reservations(
             %{organization_id: organization.id},
             cutoff
           ) do
        {:ok, _released_count} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
