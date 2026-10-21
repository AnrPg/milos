defmodule Palee.Workers.EventRemindersJob do
  @moduledoc "Every ten minutes: reminds people going to club events starting within two hours (ADR-153)."

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 300]

  alias Palee.Application.EventReminders

  @impl Oban.Worker
  def perform(_job), do: EventReminders.call()
end
