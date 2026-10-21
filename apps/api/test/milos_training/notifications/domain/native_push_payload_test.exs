defmodule MilosTraining.Notifications.Domain.NativePushPayloadTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Notifications.Domain.NativePushPayload

  @message %{
    title: "Η κράτηση εγκρίθηκε",
    body: "CrossFit, Τρίτη 18:00",
    url: "/org/box/box/schedule",
    notification_id: "n-1"
  }

  test "the FCM message carries the text and the link as data" do
    assert %{
             "message" => %{
               "token" => "tok",
               "notification" => %{"title" => "Η κράτηση εγκρίθηκε"},
               "data" => %{"url" => "/org/box/box/schedule", "notification_id" => "n-1"},
               "android" => %{"priority" => "high"}
             }
           } = NativePushPayload.fcm("tok", @message)
  end

  test "the APNs payload has an alert and the link beside aps" do
    payload = NativePushPayload.apns(@message)

    assert payload["aps"]["alert"] == %{
             "title" => "Η κράτηση εγκρίθηκε",
             "body" => "CrossFit, Τρίτη 18:00"
           }

    assert payload["url"] == "/org/box/box/schedule"
  end

  test "missing fields are left out and long text is cut" do
    payload = NativePushPayload.apns(%{body: String.duplicate("α", 2_000)})
    refute Map.has_key?(payload, "url")
    assert payload["aps"]["alert"]["title"] == "Milos"
    assert String.length(payload["aps"]["alert"]["body"]) == 600
  end

  test "APNs headers name the topic and the provider token" do
    headers = NativePushPayload.apns_headers("app.milos.member", "jwt")
    assert {"apns-topic", "app.milos.member"} in headers
    assert {"authorization", "bearer jwt"} in headers
    assert {"apns-push-type", "alert"} in headers
  end

  test "FCM answers are read into delivered, gone or an error" do
    assert NativePushPayload.fcm_result(200, %{}) == :ok
    assert NativePushPayload.fcm_result(404, %{}) == {:error, :expired}

    unregistered = %{"error" => %{"details" => [%{"errorCode" => "UNREGISTERED"}]}}
    assert NativePushPayload.fcm_result(400, unregistered) == {:error, :expired}

    bad_token = %{
      "error" => %{"details" => [%{"fieldViolations" => [%{"field" => "message.token"}]}]}
    }

    assert NativePushPayload.fcm_result(400, bad_token) == {:error, :expired}
    assert {:error, {:http_error, 400, _}} = NativePushPayload.fcm_result(400, %{"error" => %{}})
    assert {:error, {:http_error, 503, _}} = NativePushPayload.fcm_result(503, "down")
  end

  test "APNs answers are read into delivered, gone or an error" do
    assert NativePushPayload.apns_result(200, "") == :ok
    assert NativePushPayload.apns_result(410, %{"reason" => "Unregistered"}) == {:error, :expired}

    assert NativePushPayload.apns_result(400, %{"reason" => "BadDeviceToken"}) ==
             {:error, :expired}

    assert {:error, {:http_error, 429, _}} =
             NativePushPayload.apns_result(429, %{"reason" => "TooManyRequests"})
  end
end
