defmodule Palee.Workers.ClassWorkoutAlertsJob do
  @moduledoc "Every five minutes: tells staff about today's classes still without a WOD (ADR-176)."

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 120]

  alias Palee.Application.ClassWorkoutAlerts

  @impl Oban.Worker
  def perform(_job), do: ClassWorkoutAlerts.call()
end
