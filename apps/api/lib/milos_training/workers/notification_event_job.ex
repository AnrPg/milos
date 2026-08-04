defmodule MilosTraining.Workers.NotificationEventJob do
  use Oban.Worker, queue: :notifications, max_attempts: 10

  alias MilosTraining.Notifications
  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "payload" => payload} = args}) do
    case Map.get(args, "organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        RepoContext.run(%{organization_id: organization_id}, fn ->
          Notifications.process_event(event, payload)
        end)

      _missing_scope ->
        Notifications.process_event(event, payload)
    end
  end
end
