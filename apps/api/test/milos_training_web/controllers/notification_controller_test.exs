defmodule MilosTrainingWeb.NotificationControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Analytics
  alias MilosTraining.Notifications

  import MilosTraining.TestFixtures

  setup do
    user = user_fixture()

    conn =
      build_conn()
      |> put_bearer_token(user)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user}
  end

  test "lists notifications with unread count", %{conn: conn, user: user} do
    {:ok, _read_notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"},
        read_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _unread_notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_pending,
        payload: %{url: "/schedule"}
      })

    response =
      conn
      |> get("/api/notifications")
      |> json_response(200)

    assert response["unread_count"] == 1
    assert length(response["notifications"]) == 2
  end

  test "excludes chat delivery records from Updates and its unread count", %{
    conn: conn,
    user: user
  } do
    {:ok, chat_delivery} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :chat_message,
        payload: %{
          thread_id: Ecto.UUID.generate(),
          message_id: Ecto.UUID.generate(),
          body: "Shown in Messages only"
        }
      })

    {:ok, update} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"}
      })

    response =
      conn
      |> get("/api/notifications")
      |> json_response(200)

    assert chat_delivery.type == "chat_message"
    assert response["unread_count"] == 1
    assert Enum.map(response["notifications"], & &1["id"]) == [update.id]
  end

  test "marks a single notification as read", %{conn: conn, user: user} do
    {:ok, notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"}
      })

    response =
      conn
      |> post("/api/notifications/#{notification.id}/read")
      |> json_response(200)

    assert response == %{"read" => true}

    {:ok, inbox} = Notifications.list_inbox(user.id)
    [updated_notification] = inbox.notifications
    assert updated_notification.id == notification.id
    assert updated_notification.read_at != nil
  end

  test "records notification clickthrough and marks the notification read", %{
    conn: conn,
    user: user
  } do
    {:ok, notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"}
      })

    response =
      conn
      |> post("/api/notifications/#{notification.id}/click", %{url: "/schedule"})
      |> json_response(200)

    assert response == %{"clicked" => true, "read" => true}

    {:ok, inbox} = Notifications.list_inbox(user.id)
    [updated_notification] = inbox.notifications
    assert updated_notification.read_at != nil

    summary = Analytics.analytics_summary(%{"days" => "1"})
    assert summary.notification_clicks.total >= 1
    assert summary.events.by_name["notification_clicked"] >= 1
  end

  test "creates workout moved notifications", %{user: user} do
    assert {:ok, notification} =
             Notifications.create_notification(%{
               user_id: user.id,
               type: :workout_moved,
               payload: %{
                 assigned_workout_id: Ecto.UUID.generate(),
                 athlete_nickname: "atlas",
                 workout_title: "Tempo Pull",
                 body: "atlas moved Tempo Pull.",
                 url: "/my-workouts"
               }
             })

    assert notification.type == "workout_moved"
  end

  test "admin workout action notifications deep link to coaching assignments" do
    admin = admin_fixture()
    assignment_id = Ecto.UUID.generate()

    assert :ok =
             Notifications.enqueue_workout_rejected(%{
               assigned_workout_id: assignment_id,
               athlete_nickname: "atlas",
               workout_title: "Tempo Pull",
               scheduled_for: ~D[2026-06-17]
             })

    assert :ok =
             Notifications.enqueue_workout_moved(%{
               assigned_workout_id: assignment_id,
               athlete_nickname: "atlas",
               workout_title: "Tempo Pull",
               from_date: ~D[2026-06-17],
               to_date: ~D[2026-06-18]
             })

    urls =
      admin.id
      |> Notifications.list_for_user()
      |> Enum.map(& &1.payload["url"])

    assert "/admin/coaching-assignments?open_assignment=#{assignment_id}&date=2026-06-17" in urls

    assert "/admin/coaching-assignments?open_assignment=#{assignment_id}&date=2026-06-18" in urls
  end

  test "marks all visible unread notifications as read", %{conn: conn, user: user} do
    {:ok, _first_notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"}
      })

    {:ok, _second_notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_rejected,
        payload: %{url: "/schedule"}
      })

    response =
      conn
      |> post("/api/notifications/read-all")
      |> json_response(200)

    assert response == %{"marked_count" => 2}

    {:ok, inbox} = Notifications.list_inbox(user.id)
    assert Enum.all?(inbox.notifications, &(&1.read_at != nil))
    assert inbox.unread_count == 0
  end

  test "saves and deletes push subscriptions for the current user", %{conn: conn, user: user} do
    create_response =
      conn
      |> post("/api/notifications/push-subscriptions", %{
        endpoint: "https://push.example.test/subscription",
        expiration_time: nil,
        keys: %{
          p256dh: "p256dh-key",
          auth: "auth-key"
        }
      })
      |> json_response(201)

    assert create_response["subscription"]["user_id"] == user.id

    assert [%{endpoint: "https://push.example.test/subscription"}] =
             Notifications.get_push_subscriptions(user.id)

    status_response =
      conn
      |> post("/api/notifications/push-subscriptions/status", %{
        endpoint: "https://push.example.test/subscription"
      })
      |> json_response(200)

    assert status_response["registered"] == true
    assert status_response["subscription"]["endpoint"] == "https://push.example.test/subscription"

    delete_response =
      conn
      |> delete(
        "/api/notifications/push-subscriptions?endpoint=https://push.example.test/subscription"
      )
      |> json_response(200)

    assert delete_response["deleted"] == true
    assert Notifications.get_push_subscriptions(user.id) == []
  end

  test "reports when a push subscription endpoint is not persisted", %{conn: conn} do
    response =
      conn
      |> post("/api/notifications/push-subscriptions/status", %{
        endpoint: "https://push.example.test/missing"
      })
      |> json_response(200)

    assert response == %{
             "registered" => false,
             "subscription" => nil
           }
  end

  test "rejects malformed push-subscription delete requests", %{conn: conn} do
    response =
      conn
      |> delete("/api/notifications/push-subscriptions")
      |> json_response(422)

    assert response["errors"] != []
  end

  test "exposes push configuration without private key data", %{conn: conn} do
    previous_config = Application.get_env(:web_push_elixir, :vapid_config)

    Application.put_env(:web_push_elixir, :vapid_config,
      vapid_public_key: "public-key",
      vapid_private_key: "private-key",
      vapid_subject: "mailto:test@example.com"
    )

    on_exit(fn ->
      if previous_config do
        Application.put_env(:web_push_elixir, :vapid_config, previous_config)
      else
        Application.delete_env(:web_push_elixir, :vapid_config)
      end
    end)

    response_conn =
      conn
      |> get("/api/notifications/push-config")

    response = json_response(response_conn, 200)

    assert get_resp_header(response_conn, "cache-control") == ["no-store"]

    assert response == %{
             "enabled" => true,
             "vapid_public_key" => "public-key"
           }
  end
end
