defmodule MilosTraining.Workers.NotificationEventJob do
  use Oban.Worker, queue: :notifications, max_attempts: 10

  alias MilosTraining.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "payload" => payload}}) do
    Notifications.process_event(event, payload)
  end
end
