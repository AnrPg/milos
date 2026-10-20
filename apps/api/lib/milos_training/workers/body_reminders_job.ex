defmodule MilosTraining.Workers.BodyRemindersJob do
  @moduledoc "Daily: reminds people who opted in that a new body measurement is due (ADR-158)."

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.Application.BodyReminders

  @impl Oban.Worker
  def perform(_job), do: BodyReminders.call()
end
