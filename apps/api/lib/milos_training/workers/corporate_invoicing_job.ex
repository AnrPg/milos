defmodule MilosTraining.Workers.CorporateInvoicingJob do
  @moduledoc """
  Daily corporate invoicing (ADR-098): issues due invoices, marks unpaid ones
  overdue and reminds billing contacts, per active organization.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.Application.CorporateInvoicing
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(&CorporateInvoicing.run(&1, today))

    :ok
  end
end
