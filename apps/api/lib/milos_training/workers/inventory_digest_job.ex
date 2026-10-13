defmodule MilosTraining.Workers.InventoryDigestJob do
  @moduledoc """
  Every morning, tells the people who look after each gym's inventory what
  needs attention: running-low reports and stock, service due or soon,
  machines not working, and yesterday's machine notes (ADR-104). Quiet days
  send nothing.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.Organizations
  alias MilosTraining.Application.ManageInventory

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      ManageInventory.send_digest(%{organization_id: organization.id, user_id: nil}, now)
    end)

    :ok
  end
end
