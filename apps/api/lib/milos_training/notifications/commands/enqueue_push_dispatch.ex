defmodule MilosTraining.Notifications.Commands.EnqueuePushDispatch do
  alias MilosTraining.Notifications.Queries.ListPushSubscriptions
  alias MilosTraining.Workers.PushDispatchJob

  def call(notification) do
    notification.user_id
    |> ListPushSubscriptions.call()
    |> Enum.reduce([], fn subscription, errors ->
      notification
      |> build_job(subscription.endpoint)
      |> insert_job()
      |> case do
        {:ok, _job} -> errors
        {:error, reason} -> [reason | errors]
      end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, {:push_enqueue_partial_failure, Enum.reverse(errors)}}
    end
  end

  defp build_job(notification, endpoint) do
    PushDispatchJob.new(%{
      "user_id" => notification.user_id,
      "endpoint" => endpoint,
      "type" => notification.type,
      "payload" => notification.payload,
      "organization_id" => Map.get(notification, :organization_id),
      "notification_id" => notification.id
    })
  end

  defp insert_job(job) do
    Oban.insert(job)
  rescue
    RuntimeError -> {:error, :oban_unavailable}
  end
end
