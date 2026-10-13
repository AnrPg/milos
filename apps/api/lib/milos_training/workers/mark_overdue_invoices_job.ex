defmodule MilosTraining.Workers.MarkOverdueInvoicesJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.{Finance, Organizations}

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      Finance.mark_overdue_invoices(%{organization_id: organization.id})
    end)

    :ok
  end
end
