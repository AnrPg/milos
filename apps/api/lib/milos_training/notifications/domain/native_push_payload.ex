defmodule MilosTraining.Notifications.Domain.NativePushPayload do
  @moduledoc """
  Pure builders and result readers for native push (ADR-171).

  The message is the one web push sends (title, body, url, notification id);
  tapping the notification in the app opens `url` in the web view, exactly as
  the service worker does on the web. Text is cut so the payload stays far
  below the providers' 4 KB limit.
  """

  @title_limit 120
  @body_limit 600

  @doc "The FCM HTTP v1 `messages:send` body for one Android token."
  def fcm(token, message) when is_binary(token) and is_map(message) do
    %{
      "message" => %{
        "token" => token,
        "notification" => %{"title" => title(message), "body" => body(message)},
        "data" => data(message),
        "android" => %{
          "priority" => "high",
          "notification" => %{"channel_id" => "default"}
        }
      }
    }
  end

  @doc "The APNs JSON payload."
  def apns(message) when is_map(message) do
    Map.merge(
      %{
        "aps" => %{
          "alert" => %{"title" => title(message), "body" => body(message)},
          "sound" => "default"
        }
      },
      data(message)
    )
  end

  @doc "The APNs request headers for an alert to `topic` (the app's bundle id)."
  def apns_headers(topic, provider_token) do
    [
      {"authorization", "bearer " <> provider_token},
      {"apns-topic", topic},
      {"apns-push-type", "alert"},
      {"apns-priority", "10"}
    ]
  end

  @doc """
  Reads an FCM response: 200 is delivered; `UNREGISTERED` (404) or an invalid
  registration token (400) mean the install is gone.
  """
  def fcm_result(200, _body), do: :ok
  def fcm_result(404, _body), do: {:error, :expired}

  def fcm_result(400, body) do
    if fcm_token_error?(body),
      do: {:error, :expired},
      else: {:error, {:http_error, 400, body}}
  end

  def fcm_result(status, body), do: {:error, {:http_error, status, body}}

  @doc """
  Reads an APNs response: 200 is delivered; 410, `BadDeviceToken`,
  `DeviceTokenNotForTopic` and `Unregistered` mean the token is gone.
  """
  def apns_result(200, _body), do: :ok
  def apns_result(410, _body), do: {:error, :expired}

  def apns_result(400, %{"reason" => reason})
      when reason in ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"],
      do: {:error, :expired}

  def apns_result(status, body), do: {:error, {:http_error, status, body}}

  defp fcm_token_error?(%{"error" => %{"details" => details}}) when is_list(details) do
    Enum.any?(details, &(&1["errorCode"] == "UNREGISTERED")) or
      Enum.any?(details, fn detail ->
        Enum.any?(List.wrap(detail["fieldViolations"]), &(&1["field"] == "message.token"))
      end)
  end

  defp fcm_token_error?(%{"error" => %{"message" => message}}) when is_binary(message),
    do: String.contains?(message, "registration token")

  defp fcm_token_error?(_body), do: false

  defp data(message) do
    %{
      "url" => value(message, :url),
      "notification_id" => value(message, :notification_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp title(message), do: message |> value(:title) |> Kernel.||("Milos") |> cut(@title_limit)
  defp body(message), do: message |> value(:body) |> Kernel.||("") |> cut(@body_limit)

  defp value(message, key) do
    case Map.get(message, key) || Map.get(message, Atom.to_string(key)) do
      value when is_binary(value) and value != "" -> value
      _missing -> nil
    end
  end

  defp cut(text, limit) do
    if String.length(text) > limit,
      do: String.slice(text, 0, limit - 1) <> "…",
      else: text
  end
end
