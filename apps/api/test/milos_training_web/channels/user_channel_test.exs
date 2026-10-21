defmodule MilosTrainingWeb.UserChannelTest do
  @moduledoc """
  ADR-160 live updates: a person's own `user:<id>` topic (only their token
  may join it) carries one `buddy:changed` event per Buddy change, to the
  people concerned only, with ids and never words or phone numbers.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures
  require Phoenix.ChannelTest

  alias MilosTraining.Application.SupportRequests
  alias MilosTraining.Infrastructure.Auth.Guardian
  alias MilosTrainingWeb.{UserChannel, UserSocket}
  alias Phoenix.Socket.Broadcast

  setup %{conn: conn} do
    %{
      member: user_fixture(),
      buddy: user_fixture(),
      other: user_fixture(),
      as: fn user -> put_bearer_token(conn, user) end
    }
  end

  defp socket_for(user) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp listen(users), do: Enum.each(users, &@endpoint.subscribe("user:#{&1.id}"))

  defp assert_changed(user, kind) do
    topic = "user:#{user.id}"

    assert_receive %Broadcast{
      topic: ^topic,
      event: "buddy:changed",
      payload: %{kind: ^kind} = payload
    }

    payload
  end

  defp refute_changed(user, kind) do
    topic = "user:#{user.id}"
    refute_receive %Broadcast{topic: ^topic, event: "buddy:changed", payload: %{kind: ^kind}}, 50
  end

  # A buddy link through an invite link: no shared gym needed.
  defp linked!(%{as: as, member: member, buddy: buddy}) do
    %{"token" => token} =
      as.(member) |> post("/api/me/buddies/invite-links") |> json_response(201)

    %{"link" => %{"id" => link_id}} =
      as.(buddy) |> post("/api/me/buddy-invites/#{token}/claim") |> json_response(200)

    link_id
  end

  describe "joining" do
    test "only your own user topic, without a gym", %{member: member, other: other} do
      {:ok, socket} = socket_for(member)

      assert {:ok, _reply, _socket} =
               Phoenix.ChannelTest.subscribe_and_join(socket, UserChannel, "user:#{member.id}")

      assert {:error, %{reason: "forbidden"}} =
               Phoenix.ChannelTest.subscribe_and_join(socket, UserChannel, "user:#{other.id}")
    end

    test "a pushed event reaches the joined socket", %{member: member} do
      {:ok, socket} = socket_for(member)

      {:ok, _reply, _socket} =
        Phoenix.ChannelTest.subscribe_and_join(socket, UserChannel, "user:#{member.id}")

      @endpoint.broadcast("user:#{member.id}", "buddy:changed", %{kind: "buddy_link_changed"})
      Phoenix.ChannelTest.assert_push("buddy:changed", %{kind: "buddy_link_changed"})
    end
  end

  describe "broadcasts" do
    test "link changes reach both people", %{as: as, member: member, buddy: buddy} = ctx do
      listen([member, buddy])
      link_id = linked!(ctx)
      assert %{link_id: ^link_id} = assert_changed(member, "buddy_link_changed")
      assert_changed(buddy, "buddy_link_changed")

      as.(member)
      |> send_json(:patch, "/api/me/buddies/#{link_id}", %{receives_weekly_summary: true})
      |> json_response(200)

      assert_changed(buddy, "buddy_link_changed")

      as.(buddy) |> post("/api/me/buddies/#{link_id}/leave") |> json_response(200)
      assert_changed(member, "buddy_link_changed")
    end

    test "a request: the sender while it can be undone, buddies once delivered",
         %{as: as, member: member, buddy: buddy, other: other} = ctx do
      linked!(ctx)
      listen([member, buddy, other])

      %{"support_request" => %{"id" => undone_id}} =
        as.(member) |> send_json(:post, "/api/me/support-requests", %{}) |> json_response(201)

      assert %{request_id: ^undone_id} = assert_changed(member, "support_request_sent")
      refute_changed(buddy, "support_request_sent")

      as.(member) |> post("/api/me/support-requests/#{undone_id}/undo") |> json_response(200)
      assert_changed(member, "support_request_undone")
      refute_changed(buddy, "support_request_undone")

      %{"support_request" => %{"id" => id}} =
        as.(member)
        |> send_json(:post, "/api/me/support-requests", %{message: "Δύσκολο βράδυ."})
        |> json_response(201)

      :ok = SupportRequests.deliver(member.id, id)
      payload = assert_changed(buddy, "support_request_delivered")
      assert payload == %{kind: "support_request_delivered", request_id: id}
      assert_changed(member, "support_request_delivered")
      refute_changed(other, "support_request_delivered")

      :ok =
        SupportRequests.nudge(member.id, id, DateTime.add(DateTime.utc_now(), 11 * 60, :second))

      assert_changed(member, "support_request_nudged")
      refute_changed(buddy, "support_request_nudged")
    end

    test "a reply reaches the sender and the buddy; messages and reads reach both",
         %{as: as, member: member, buddy: buddy} = ctx do
      link_id = linked!(ctx)

      %{"support_request" => %{"id" => id}} =
        as.(member) |> send_json(:post, "/api/me/support-requests", %{}) |> json_response(201)

      :ok = SupportRequests.deliver(member.id, id)
      listen([member, buddy])

      as.(buddy)
      |> send_json(:post, "/api/me/support-requests/#{id}/replies", %{kind: "call"})
      |> json_response(201)

      payload = assert_changed(member, "support_reply_created")
      assert payload == %{kind: "support_reply_created", request_id: id, link_id: link_id}
      assert_changed(buddy, "support_reply_created")
      assert %{link_id: ^link_id} = assert_changed(member, "buddy_message_created")

      as.(member)
      |> send_json(:post, "/api/me/buddies/#{link_id}/messages", %{body: "Ευχαριστώ"})
      |> json_response(201)

      assert_changed(buddy, "buddy_message_created")
      assert_changed(member, "buddy_message_created")

      as.(buddy) |> post("/api/me/buddies/#{link_id}/messages/read") |> json_response(200)
      assert %{link_id: ^link_id} = assert_changed(member, "buddy_messages_read")
      assert_changed(buddy, "buddy_messages_read")

      # Nothing left to read: no event.
      as.(buddy) |> post("/api/me/buddies/#{link_id}/messages/read") |> json_response(200)
      refute_changed(member, "buddy_messages_read")
    end
  end
end
