defmodule PaleeWeb.MessagesToMembersTest do
  @moduledoc "ADR-140 §6/§7: coaching messages, messages from the box, Πελάτες μου stats."

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Coaching, Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    coach = person.(:coach)
    member = person.(:member)

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: organization.id}, %{
        coach_user_id: coach.id,
        client_user_id: member.id,
        origin: "assigned"
      })

    %{
      coach: coach,
      member: member,
      front_desk: person.(:front_desk),
      admin: person.(:admin),
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp thread(as, user, base, body) do
    as.(user)
    |> send_json(:post, "#{base}/me/threads", body)
    |> json_response(200)
    |> Map.fetch!("thread")
  end

  defp say(as, user, base, thread, body) do
    as.(user) |> send_json(:post, "#{base}/me/threads/#{thread["id"]}/messages", body)
  end

  test "a coach's coaching messages and the client's waiting replies count in Πελάτες μου",
       ctx do
    %{as: as, base: base, coach: coach, member: member} = ctx
    direct = thread(as, coach, base, %{context_type: "direct", participant_id: member.id})

    assert %{"message" => %{"message_type" => "coaching_message"}} =
             say(as, coach, base, direct, %{
               body: "Deload this week",
               message_type: "coaching_message"
             })
             |> json_response(201)

    assert %{"coaching_messages_this_week" => 1, "awaiting_reply" => 0, "client_count" => 1} =
             as.(coach) |> get("#{base}/staff/my-client-stats") |> json_response(200)

    assert %{"message" => %{"message_type" => "chat"}} =
             say(as, member, base, direct, %{body: "Even the squats?"}) |> json_response(201)

    assert %{"awaiting_reply" => 1} =
             as.(coach) |> get("#{base}/staff/my-client-stats") |> json_response(200)

    # The member reads it on Box › Ο coach σου.
    assert %{"coaching_messages" => [%{"body" => "Deload this week", "sender_id" => sender}]} =
             as.(member) |> get("#{base}/landing") |> json_response(200)

    assert sender == coach.id
  end

  test "operational staff write from the box on the gym's thread, any of them can continue it",
       ctx do
    %{as: as, base: base, member: member, front_desk: front_desk, admin: admin} = ctx
    box = thread(as, front_desk, base, %{context_type: "box", context_id: member.id})

    assert %{"message" => %{"message_type" => "box_message", "topic" => "payment"}} =
             say(as, front_desk, base, box, %{body: "Your card was declined", topic: "payment"})
             |> json_response(201)

    # The member answers in the same thread; it is chat from their side.
    assert %{"message" => %{"message_type" => "chat"}} =
             say(as, member, base, box, %{body: "Updated it"}) |> json_response(201)

    # Another permitted staff member reaches the same thread and continues it.
    assert thread(as, admin, base, %{context_type: "box", context_id: member.id})["id"] ==
             box["id"]

    assert %{"message" => %{"message_type" => "box_message"}} =
             say(as, admin, base, box, %{body: "Thanks!"}) |> json_response(201)

    # A message from the box belongs in the box thread, never a direct chat.
    direct = thread(as, admin, base, %{context_type: "direct", participant_id: member.id})

    assert %{"code" => "box_message_outside_box_thread"} =
             say(as, admin, base, direct, %{body: "Hi", message_type: "box_message"})
             |> json_response(422)
  end

  test "a member cannot open the box's thread with someone else", ctx do
    %{as: as, base: base, member: member} = ctx
    other = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(other)

    assert as.(other)
           |> send_json(:post, "#{base}/me/threads", %{context_type: "box", context_id: member.id})
           |> json_response(403)
  end
end
