defmodule MilosTraining.Workers.ReconcileEntitlementReservationsJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.Finance

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    case Finance.release_stale_entitlement_reservations(cutoff) do
      {:ok, _released_count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
