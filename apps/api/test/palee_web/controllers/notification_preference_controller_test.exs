defmodule PaleeWeb.NotificationPreferenceControllerTest do
  @moduledoc """
  ADR-199 over HTTP (`/api/notifications/preferences`, the caller's own
  choices only) and at the delivery chokepoints: a muted bell writes no
  notification, a muted push queues no push.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.FakeNativePushSender
  alias Palee.Notifications
  alias Palee.Notifications.Commands.DispatchNotification
  alias Palee.Workers.NativePushDispatchJob

  setup %{conn: conn} do
    %{conn: conn, member: user_fixture(), other: user_fixture()}
  end

  defp authed(ctx, user), do: ctx.conn |> recycle() |> put_bearer_token(user)

  defp channels(body, category),
    do: Enum.find(body["preferences"], &(&1["category"] == category))["channels"]

  test "defaults are on; a change is the caller's own", ctx do
    body =
      ctx |> authed(ctx.member) |> get("/api/notifications/preferences") |> json_response(200)

    assert Enum.all?(body["preferences"], &(&1["channels"]["push"] and &1["channels"]["in_app"]))

    assert %{"locked" => true} =
             Enum.find(body["preferences"], &(&1["category"] == "account"))

    changed =
      ctx
      |> authed(ctx.member)
      |> put("/api/notifications/preferences/community", %{"push" => false})
      |> json_response(200)

    assert channels(changed, "community") == %{"in_app" => true, "push" => false}

    off =
      ctx
      |> authed(ctx.member)
      |> put("/api/notifications/preferences/community", %{"in_app" => false})
      |> json_response(200)

    assert channels(off, "community") == %{"in_app" => false, "push" => false}

    others =
      ctx |> authed(ctx.other) |> get("/api/notifications/preferences") |> json_response(200)

    assert channels(others, "community") == %{"in_app" => true, "push" => true}
  end

  test "refuses a locked, unknown or empty change", ctx do
    assert %{"code" => "locked_category"} =
             ctx
             |> authed(ctx.member)
             |> put("/api/notifications/preferences/account", %{"push" => false})
             |> json_response(422)

    assert %{"code" => "unknown_category"} =
             ctx
             |> authed(ctx.member)
             |> put("/api/notifications/preferences/marketing", %{"push" => false})
             |> json_response(404)

    assert %{"code" => "invalid_change"} =
             ctx
             |> authed(ctx.member)
             |> put("/api/notifications/preferences/coach", %{})
             |> json_response(422)
  end

  describe "enforcement" do
    setup do
      start_supervised!(
        {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
      )

      FakeNativePushSender.enable([:fcm])

      on_exit(fn -> FakeNativePushSender.disable() end)
      :ok
    end

    defp mute(user, category, params) do
      context = %{user_id: user.id}
      assert {:ok, _preferences} = Notifications.update_preference(context, category, params)
    end

    defp register_install(user) do
      {:ok, token, :created} =
        Notifications.register_native_push_token(user.id, %{
          "provider" => "fcm",
          "platform" => "android",
          "token" => "fcm-" <> String.duplicate("p", 30)
        })

      token
    end

    test "a muted bell writes nothing and pushes nothing", ctx do
      install = register_install(ctx.member)
      mute(ctx.member, "journal", %{"in_app" => false})

      assert :ok = DispatchNotification.call(ctx.member.id, :water_reminder, %{})
      assert Notifications.list_for_user(ctx.member.id) == []
      refute_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => install.id})

      assert :ok =
               Notifications.create_notification(%{
                 user_id: ctx.member.id,
                 type: :body_measure_reminder,
                 payload: %{}
               })

      assert Notifications.list_for_user(ctx.member.id) == []
    end

    test "a muted push keeps the bell and queues no push", ctx do
      install = register_install(ctx.member)
      mute(ctx.member, "bookings", %{"push" => false})

      assert {:ok, _notification} =
               DispatchNotification.call(ctx.member.id, :booking_approved, %{"url" => "/box"})

      assert [%{type: "booking_approved"}] = Notifications.list_for_user(ctx.member.id)
      refute_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => install.id})

      assert {:ok, _notification} =
               DispatchNotification.call(ctx.member.id, :person_message, %{"url" => "/messages"})

      assert_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => install.id})
    end

    test "a locked category is delivered whatever is stored", ctx do
      install = register_install(ctx.member)

      Palee.Infrastructure.Tenancy.RepoContext.run(%{user_id: ctx.member.id}, fn ->
        Palee.Repo.insert_all("notification_preferences", [
          %{
            user_id: Ecto.UUID.dump!(ctx.member.id),
            category: "account",
            channel: "in_app",
            enabled: false,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ])
      end)

      assert {:ok, _notification} =
               DispatchNotification.call(ctx.member.id, :payment_reminder, %{"url" => "/me"})

      assert [%{type: "payment_reminder"}] = Notifications.list_for_user(ctx.member.id)
      assert_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => install.id})
    end
  end
end
