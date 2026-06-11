defmodule MilosTraining.Workers.PushDispatchJob do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MilosTraining.Notifications
  alias MilosTraining.Notifications.Domain.PushMessageBuilder
  alias MilosTraining.Notifications.Queries.GetPushSubscription

  defp dispatcher do
    Application.get_env(
      :milos_training,
      :push_dispatcher,
      MilosTraining.Infrastructure.Notifications.WebPushDispatcher
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "user_id" => user_id,
            "endpoint" => endpoint,
            "type" => type,
            "payload" => payload
          } = args
      }) do
    notification_id = Map.get(args, "notification_id")

    case GetPushSubscription.call(user_id, endpoint) do
      nil ->
        :ok

      subscription ->
        message =
          PushMessageBuilder.build(type, payload)
          |> Map.put(:notification_id, notification_id)

        case dispatcher().send_push(subscription, message) do
          :ok ->
            :ok

          {:error, :expired} ->
            Notifications.delete_push_subscription(user_id, endpoint)
            :ok

          {:error, reason} ->
            Logger.warning(
              "push_dispatch_failed user_id=#{user_id} endpoint=#{endpoint} reason=#{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end
end
