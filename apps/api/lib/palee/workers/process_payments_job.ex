defmodule Palee.Workers.ProcessPaymentsJob do
  @moduledoc """
  ADR-246/247: every few minutes settles open online payments for every
  business (polling the provider when a webhook was lost, dunning declined
  saved cards, fulfilling succeeded payments). With `"autopay"` it first
  charges saved cards for due invoices (hourly, so each time zone pays on
  its own day).
  """

  use Oban.Worker, queue: :payments, max_attempts: 3, unique: [period: 60]

  require Logger

  alias Palee.Application.Payments.OnlinePayments
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      context = %{organization_id: organization.id}

      try do
        if args["autopay"], do: OnlinePayments.autopay(context, now)
        OnlinePayments.process(context, now)
      rescue
        error ->
          Logger.error(
            "online payments failed for #{organization.id}: #{Exception.message(error)}"
          )
      end
    end)

    :ok
  end
end
