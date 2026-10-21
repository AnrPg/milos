defmodule MilosTraining.Workers.NativePushDispatchJob do
  @moduledoc """
  Sends one notification to one store app install (ADR-171), like
  `PushDispatchJob` does for a browser: same message, same delivery outcome
  analytics (the install is hashed, never stored), and a token the provider
  says is gone is deleted.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MilosTraining.Application.RecordPushDeliveryOutcome
  alias MilosTraining.Notifications
  alias MilosTraining.Notifications.Domain.PushMessageBuilder
  alias MilosTraining.Notifications.NativePush

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "user_id" => user_id,
              "token_id" => token_id,
              "type" => type,
              "payload" => payload
            } = args
        } = job
      ) do
    case Notifications.get_native_push_token(user_id, token_id) do
      nil ->
        :ok

      token ->
        message =
          %{
            title: payload["title"],
            body: payload["body"],
            url: payload["url"],
            locale: payload["locale"]
          }
          |> fallback_message(type, payload)
          |> Map.put(:notification_id, args["notification_id"])

        result = NativePush.send_push(token, message)

        RecordPushDeliveryOutcome.call(
          Map.put(args, "endpoint", "native:#{token.provider}:#{token.id}"),
          result,
          job.attempt || 1,
          job.max_attempts || 1
        )

        handle(result, user_id, token)
    end
  end

  defp handle(:ok, _user_id, _token), do: :ok

  defp handle({:error, :expired}, user_id, token) do
    Notifications.delete_native_push_token_by_id(user_id, token.id)
    :ok
  end

  # Credentials were removed after the job was queued: nothing to retry.
  defp handle({:error, :push_not_configured}, _user_id, _token), do: :ok

  defp handle({:error, reason}, user_id, token) do
    Logger.warning(
      "native_push_dispatch_failed user_id=#{user_id} provider=#{token.provider} reason=#{inspect(reason)}"
    )

    {:error, reason}
  end

  defp fallback_message(%{title: title, body: body} = message, _type, _payload)
       when is_binary(title) and is_binary(body),
       do: message

  defp fallback_message(_message, type, payload), do: PushMessageBuilder.build(type, payload)
end
