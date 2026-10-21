defmodule Palee.Notifications.Commands.EnqueueNativePushDispatch do
  @moduledoc """
  One native push job per store app install of the recipient whose provider
  is configured (ADR-171). Runs inside the recipient's session, next to the
  web push enqueue.
  """

  alias Palee.Notifications.NativePush
  alias Palee.Notifications.Queries.ListNativePushTokens
  alias Palee.Workers.NativePushDispatchJob

  def call(notification) do
    case NativePush.configured_providers() do
      [] ->
        :ok

      providers ->
        notification.user_id
        |> ListNativePushTokens.call()
        |> Enum.filter(&(&1.provider in providers))
        |> Enum.reduce([], fn token, errors ->
          case insert_job(build_job(notification, token)) do
            {:ok, _job} -> errors
            {:error, reason} -> [reason | errors]
          end
        end)
        |> case do
          [] -> :ok
          errors -> {:error, {:native_push_enqueue_partial_failure, Enum.reverse(errors)}}
        end
    end
  end

  defp build_job(notification, token) do
    NativePushDispatchJob.new(%{
      "user_id" => notification.user_id,
      "token_id" => token.id,
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
