defmodule MilosTraining.Infrastructure.Notifications.WebPushDispatcher do
  @behaviour MilosTraining.Notifications.Ports.PushDispatcher

  alias MilosTraining.Notifications.PushConfig

  @impl true
  def send_push(subscription, message) do
    with true <- PushConfig.enabled?(),
         true <- Code.ensure_loaded?(WebPushElixir) do
      subscription
      |> encode_subscription()
      |> WebPushElixir.send_notification(Jason.encode!(message))
      |> normalize_result()
    else
      false -> {:error, :push_not_configured}
    end
  end

  defp encode_subscription(subscription) do
    Jason.encode!(%{
      endpoint: subscription.endpoint,
      keys: %{
        p256dh: subscription.keys["p256dh"] || subscription.keys[:p256dh],
        auth: subscription.keys["auth"] || subscription.keys[:auth]
      }
    })
  end

  defp normalize_result({:ok, _response}), do: :ok
  defp normalize_result({:error, reason}), do: normalize_error(reason)
  defp normalize_result(reason), do: normalize_error(reason)

  defp normalize_error(:expired), do: {:error, :expired}
  defp normalize_error(reason), do: {:error, reason}
end
