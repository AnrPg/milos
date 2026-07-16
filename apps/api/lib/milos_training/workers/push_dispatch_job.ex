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
          %{
            title: payload["title"],
            body: payload["body"],
            url: payload["url"],
            locale: payload["locale"]
          }
          |> fallback_message(type, payload)
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

  defp fallback_message(%{title: title, body: body} = message, _type, _payload)
       when is_binary(title) and is_binary(body),
       do: message

  defp fallback_message(_message, type, payload), do: PushMessageBuilder.build(type, payload)
end
