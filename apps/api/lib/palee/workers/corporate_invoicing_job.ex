defmodule Palee.Workers.CorporateInvoicingJob do
  @moduledoc """
  Daily corporate invoicing (ADR-098): issues due invoices, marks unpaid ones
  overdue and reminds billing contacts, per active organization.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Organizations
  alias Palee.Application.CorporateInvoicing

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(&CorporateInvoicing.run(&1, today))

    :ok
  end
end
