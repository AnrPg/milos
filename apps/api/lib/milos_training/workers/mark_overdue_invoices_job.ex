defmodule MilosTraining.Workers.MarkOverdueInvoicesJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.Finance
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} ->
      Finance.mark_overdue_invoices(%{organization_id: organization.id})
    end)

    :ok
  end
end
