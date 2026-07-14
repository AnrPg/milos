defmodule MilosTraining.Notifications.Commands.DispatchNotification do
  alias MilosTraining.Notifications.Commands.CreateNotification
  alias MilosTraining.Notifications.Commands.EnqueuePushDispatch
  alias MilosTraining.Notifications.Domain.{PayloadNormalizer, PushMessageBuilder}
  alias MilosTraining.Notifications.PushConfig

  def call(user_id, type, payload) do
    normalized_payload =
      payload
      |> PayloadNormalizer.normalize()
      |> enrich_payload(type)

    with {:ok, notification} <-
           CreateNotification.call(%{
             user_id: user_id,
             type: type,
             dedupe_key: Map.get(payload, :dedupe_key) || Map.get(payload, "dedupe_key"),
             payload: normalized_payload
           }) do
      case notification do
        :duplicate ->
          :ok

        _notification ->
          case maybe_enqueue_push(notification) do
            :ok -> {:ok, notification}
            {:error, reason} -> {:error, {:push_enqueue_failed, notification, reason}}
          end
      end
    end
  end

  defp maybe_enqueue_push(notification) do
    if PushConfig.enabled?() do
      EnqueuePushDispatch.call(notification)
    else
      :ok
    end
  end

  defp enrich_payload(payload, type) do
    message = PushMessageBuilder.build(type, payload)

    payload
    |> Map.put_new("title", message.title)
    |> Map.put_new("body", message.body)
    |> Map.put_new("url", message.url)
  end
end
