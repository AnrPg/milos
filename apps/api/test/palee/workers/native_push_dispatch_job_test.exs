defmodule Palee.Workers.NativePushDispatchJobTest do
  # ADR-171: notifications reach the store apps next to web push.
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  alias Palee.FakeNativePushSender
  alias Palee.Notifications
  alias Palee.Notifications.Commands.DispatchNotification
  alias Palee.Workers.NativePushDispatchJob

  import Palee.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    FakeNativePushSender.subscribe()

    on_exit(fn ->
      FakeNativePushSender.unsubscribe()
      FakeNativePushSender.disable()
    end)

    FakeNativePushSender.enable([:fcm, :apns])
    {:ok, user: user_fixture()}
  end

  defp register(user, provider, token) do
    platform = if provider == "fcm", do: "android", else: "ios"

    {:ok, registered, :created} =
      Notifications.register_native_push_token(user.id, %{
        "provider" => provider,
        "platform" => platform,
        "token" => token
      })

    registered
  end

  defp job_args(user, token) do
    %{
      "user_id" => user.id,
      "token_id" => token.id,
      "type" => "booking_approved",
      "payload" => %{"title" => "Εγκρίθηκε", "body" => "CrossFit 18:00", "url" => "/box"},
      "notification_id" => Ecto.UUID.generate()
    }
  end

  test "a new notification queues one job per install whose provider is on", %{user: user} do
    android = register(user, "fcm", "fcm-" <> String.duplicate("a", 30))
    iphone = register(user, "apns", String.duplicate("b", 64))
    FakeNativePushSender.enable([:fcm])

    assert {:ok, _notification} =
             DispatchNotification.call(user.id, :booking_approved, %{
               "training_type" => "crossfit",
               "url" => "/schedule"
             })

    assert_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => android.id})
    refute_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => iphone.id})
  end

  test "the job sends the notification to the install", %{user: user} do
    token = register(user, "apns", String.duplicate("c", 64))

    assert :ok = perform_job(NativePushDispatchJob, job_args(user, token))

    assert_received {:native_push, :apns, %{id: id}, %{title: "Εγκρίθηκε", url: "/box"}}
    assert id == token.id
  end

  test "a token the provider says is gone is deleted", %{user: user} do
    token = register(user, "fcm", "gone-" <> String.duplicate("d", 30))
    keep = register(user, "fcm", "keep-" <> String.duplicate("e", 30))

    assert :ok = perform_job(NativePushDispatchJob, job_args(user, token))

    assert [%{id: id}] = Notifications.list_native_push_tokens(user.id)
    assert id == keep.id
  end

  test "a provider error is retried", %{user: user} do
    token = register(user, "fcm", "fail-" <> String.duplicate("f", 30))

    assert {:error, {:http_error, 500, _}} =
             NativePushDispatchJob.perform(%Oban.Job{args: job_args(user, token)})
  end

  test "an install that is gone already is skipped", %{user: user} do
    token = register(user, "fcm", "fcm-" <> String.duplicate("g", 30))
    Notifications.delete_native_push_token(user.id, token.token)

    assert :ok = perform_job(NativePushDispatchJob, job_args(user, token))
    refute_received {:native_push, _, _, _}
  end
end
