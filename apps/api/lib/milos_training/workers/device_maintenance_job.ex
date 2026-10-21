defmodule MilosTraining.Workers.DeviceMaintenanceJob do
  @moduledoc "Every 15 minutes: refreshes device tokens that end soon (ADR-161)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 600]

  alias MilosTraining.Application.DeviceMaintenance

  @impl Oban.Worker
  def perform(_job) do
    _counts = DeviceMaintenance.call()
    :ok
  end
end
