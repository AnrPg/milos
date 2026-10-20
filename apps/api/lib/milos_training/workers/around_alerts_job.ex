defmodule MilosTraining.Workers.AroundAlertsJob do
  @moduledoc "Daily: tells people what is new for their saved Γύρω μου filters, at most once a day each (ADR-154)."

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.Application.AroundAlerts

  @impl Oban.Worker
  def perform(_job), do: AroundAlerts.call()
end
