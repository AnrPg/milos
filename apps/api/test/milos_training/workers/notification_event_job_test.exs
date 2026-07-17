defmodule MilosTraining.Workers.NotificationEventJobTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Workers.NotificationEventJob

  import MilosTraining.TestFixtures

  setup do
    previous_store = Application.get_env(:milos_training, :notification_store)
    Application.put_env(:milos_training, :notification_store, __MODULE__.FailingNotificationStore)

    on_exit(fn ->
      if previous_store do
        Application.put_env(:milos_training, :notification_store, previous_store)
      else
        Application.delete_env(:milos_training, :notification_store)
      end
    end)

    :ok
  end

  test "booking fanout preserves recipient failures for Oban retry" do
    failing_admin = admin_fixture()
    _healthy_admin = admin_fixture()
    Process.put(:fail_user_id, failing_admin.id)

    booking = %{
      "id" => Ecto.UUID.generate(),
      "user_id" => Ecto.UUID.generate(),
      "scheduled_class_id" => Ecto.UUID.generate(),
      "status" => "pending",
      "scheduled_class" => %{
        "scheduled_at" => "2026-06-13T10:00:00Z",
        "training_type" => "crossfit"
      }
    }

    assert {:error, {:notification_failed, :store_down}} =
             NotificationEventJob.perform(%Oban.Job{
               args: %{"event" => "booking_timed_out", "payload" => booking}
             })
  end

  defmodule FailingNotificationStore do
    @behaviour MilosTraining.Notifications.Ports.NotificationStore

    def create_notification(%{user_id: user_id}) do
      if user_id == Process.get(:fail_user_id) do
        {:error, :store_down}
      else
        {:ok, %{id: Ecto.UUID.generate(), user_id: user_id, payload: %{}}}
      end
    end

    def list_for_user(_user_id), do: []
    def list_inbox_page(_user_id, _opts), do: %{notifications: [], next_cursor: nil}
    def count_unread_inbox(_user_id), do: 0
    def mark_all_read(_user_id), do: 0
    def mark_read(_user_id, _notification_id), do: false
    def delete_booking_pending_for_booking(_booking_id), do: :ok
    def propagate_nickname_change(_old_nickname, _new_nickname), do: :ok
    def get_push_settings, do: %{}
    def get_push_delivery_config, do: %{}
    def update_push_settings(settings), do: {:ok, settings}
  end
end
