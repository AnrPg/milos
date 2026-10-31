defmodule Palee.Workers.LapsePackageRequestsJob do
  @moduledoc """
  ADR-291: hourly, closes as `lapsed` the packages that waited 14 days for
  payment at the desk, in each box's own day. Queues and the person's app
  already hide them from the day after their hold; this records the end.
  Idempotent, so a missed run is caught up by the next.
  """

  use Oban.Worker, queue: :payments, max_attempts: 3, unique: [period: 300]

  require Logger

  alias Palee.Application.Finance.PackageRequests
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs for one organization (`context` carries its id)."
  def run(context, now \\ DateTime.utc_now()) do
    PackageRequests.lapse(context, now)
  rescue
    error ->
      Logger.error(
        "package request lapse failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      0
  end
end
