defmodule PaleeWeb.NotificationControllerTest do
  # TD-046: the inbox spans organizations; requests run under RLS.
  use PaleeWeb.ConnCase, async: false

  alias Palee.Analytics
  alias Palee.Notifications
  alias Palee.Organizations

  import Palee.TestFixtures

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

  test "counts unread notifications without loading the list, leaving out chat deliveries", %{
    conn: conn,
    user: user
  } do
    for type <- [:booking_pending, :booking_approved] do
      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: type,
          payload: %{url: "/schedule"}
        })
    end

    {:ok, _read} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :booking_approved,
        payload: %{url: "/schedule"},
        read_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _chat_delivery} =
      Notifications.create_notification(%{
        user_id: user.id,
        type: :chat_message,
        payload: %{
          thread_id: Ecto.UUID.generate(),
          message_id: Ecto.UUID.generate(),
          body: "Messages only"
        }
      })

    {:ok, _someone_else} =
      Notifications.create_notification(%{
        user_id: user_fixture().id,
        type: :booking_pending,
        payload: %{url: "/schedule"}
      })

    assert conn |> get("/api/notifications/unread-count") |> json_response(200) == %{
             "unread_count" => 2
           }
  end

  test "refuses the unread count without a session" do
    assert build_conn() |> get("/api/notifications/unread-count") |> json_response(401)
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
    {:ok, organization} = Organizations.create_organization(%{name: "Click Gym"})

    {:ok, notification} =
      Notifications.create_notification(%{
        user_id: user.id,
        organization_id: organization.id,
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

    summary =
      Palee.Analytics.AnalyticsStore.with_tenant_context(
        %{organization_id: organization.id},
        fn -> Analytics.analytics_summary(%{"days" => "1"}) end
      )

    assert summary.notification_clicks.total >= 1
    assert summary.events.by_name["notification_clicked"] >= 1
  end

  test "an organization-less notification click is marked read without a tenant click fact",
       %{conn: conn, user: user} do
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
    assert [%{read_at: %DateTime{}}] = inbox.notifications
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

    {:ok, organization} = Organizations.create_organization(%{name: "Notification Deep Link Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    assert :ok =
             Notifications.enqueue_workout_rejected(%{
               organization_id: organization.id,
               assigned_workout_id: assignment_id,
               athlete_nickname: "atlas",
               workout_title: "Tempo Pull",
               scheduled_for: ~D[2026-06-17]
             })

    assert :ok =
             Notifications.enqueue_workout_moved(%{
               organization_id: organization.id,
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
    Application.put_env(:palee, :web_push_server_keys,
      public_key: "public-key",
      private_key: "private-key",
      subject: "mailto:test@example.com"
    )

    on_exit(fn -> Application.delete_env(:palee, :web_push_server_keys) end)

    response_conn =
      conn
      |> get("/api/notifications/push-config")

    response = json_response(response_conn, 200)

    assert get_resp_header(response_conn, "cache-control") == ["no-store"]

    assert response == %{
             "enabled" => true,
             "vapid_public_key" => "public-key",
             "native_providers" => []
           }
  end
end
