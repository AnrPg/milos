defmodule MilosTraining.Notifications.Commands.EnqueuePushDispatch do
  alias MilosTraining.Notifications.Queries.ListPushSubscriptions
  alias MilosTraining.Workers.PushDispatchJob

  def call(notification) do
    notification.user_id
    |> ListPushSubscriptions.call()
    |> Enum.reduce_while(:ok, fn subscription, :ok ->
      notification
      |> build_job(subscription.endpoint)
      |> insert_job()
      |> case do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_job(notification, endpoint) do
    PushDispatchJob.new(%{
      "user_id" => notification.user_id,
      "endpoint" => endpoint,
      "type" => notification.type,
      "payload" => notification.payload,
      "notification_id" => notification.id
    })
  end

  defp insert_job(job) do
    Oban.insert(job)
  rescue
    RuntimeError -> {:error, :oban_unavailable}
  end
end
