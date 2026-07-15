defmodule MilosTraining.Workers.PushDispatchJobTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Notifications
  alias MilosTraining.Workers.PushDispatchJob

  import MilosTraining.TestFixtures

  setup do
    previous_dispatcher = Application.get_env(:milos_training, :push_dispatcher)

    Application.put_env(:milos_training, :push_dispatcher, __MODULE__.FakeDispatcher)

    on_exit(fn ->
      if previous_dispatcher do
        Application.put_env(:milos_training, :push_dispatcher, previous_dispatcher)
      else
        Application.delete_env(:milos_training, :push_dispatcher)
      end
    end)

    :ok
  end

  test "removes subscriptions reported as gone while keeping healthy ones" do
    user = user_fixture()

    {:ok, _healthy, _} =
      Notifications.save_push_subscription(user.id, %{
        endpoint: "https://push.example.test/healthy",
        expiration_time: nil,
        keys: %{"p256dh" => "key-1", "auth" => "auth-1"}
      })

    {:ok, _gone, _} =
      Notifications.save_push_subscription(user.id, %{
        endpoint: "https://push.example.test/gone",
        expiration_time: nil,
        keys: %{"p256dh" => "key-2", "auth" => "auth-2"}
      })

    assert :ok =
             PushDispatchJob.perform(%Oban.Job{
               args: %{
                 "user_id" => user.id,
                 "endpoint" => "https://push.example.test/gone",
                 "type" => "booking_approved",
                 "payload" => %{"training_type" => "crossfit"}
               }
             })

    remaining_endpoints =
      Notifications.get_push_subscriptions(user.id)
      |> Enum.map(& &1.endpoint)

    assert "https://push.example.test/healthy" in remaining_endpoints
    refute "https://push.example.test/gone" in remaining_endpoints
  end

  defmodule FakeDispatcher do
    @behaviour MilosTraining.Notifications.Ports.PushDispatcher

    @impl true
    def send_push(%{endpoint: "https://push.example.test/gone"}, _message), do: {:error, :expired}

    def send_push(_subscription, _message), do: :ok
  end
end
