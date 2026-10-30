defmodule Palee.Workers.SubscriptionChargesJob do
  @moduledoc """
  ADR-274: hourly, issues the charge for every subscription period that has
  begun (so each box's own day starts its periods, whatever its time zone).
  Issuing is idempotent per period, so a missed run is caught up by the next.
  """

  use Oban.Worker, queue: :payments, max_attempts: 3, unique: [period: 300]

  require Logger

  alias Palee.{Finance, Organizations}

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs the charges for one organization (`context` carries its id)."
  def run(context, today \\ nil) do
    today = today || Organizations.local_today(context.organization_id)
    Finance.charge_due_subscriptions(context, today)
  rescue
    error ->
      Logger.error(
        "subscription charges failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      []
  end
end
