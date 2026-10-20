defmodule MilosTrainingWeb.BuddiesControllerTest do
  @moduledoc """
  ADR-160 (P2-M12, Buddy για στήριξη) end to end under row security:
  invitations, acceptance and quiet leaving, off-platform invite links,
  «Χρειάζομαι στήριξη» with the 5-second undo, delivery (silent in quiet
  hours), replies that open the pair's conversation, phone sharing, the
  no-reply card, the weekly counts summary and the coach summary that
  needs the member's grant.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{BuddyWeeklySummaries, SupportRequests}
  alias MilosTraining.Messaging.Message
  alias MilosTraining.Notifications.Notification
  alias MilosTraining.{Coaching, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, gym} = Organizations.create_organization(%{name: "Buddy Box"})
    member = user_fixture()
    dimitra = user_fixture()
    kostas = user_fixture()
    coach = user_fixture()
    stranger = user_fixture()

    for {user, role} <- [
          {member, :member},
          {dimitra, :member},
          {kostas, :member},
          {coach, :coach}
        ] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: gym.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: gym.id}, %{
        coach_user_id: coach.id,
        client_user_id: member.id,
        origin: "assigned"
      })

    %{
      gym: gym,
      member: member,
      dimitra: dimitra,
      kostas: kostas,
      coach: coach,
      stranger: stranger,
      as: fn user -> put_bearer_token(conn, user) end
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp notifications(user, type) do
    Repo.all(from(n in Notification, where: n.user_id == ^user.id and n.type == ^type))
  end

  defp invite!(as, from, to) do
    as.(from)
    |> send_json(:post, "/api/me/buddies", %{user_id: to.id})
    |> json_response(201)
    |> Map.fetch!("link")
  end

  defp buddies!(as, member, buddy) do
    link = invite!(as, member, buddy)
    as.(buddy) |> post("/api/me/buddies/#{link["id"]}/accept") |> json_response(200)
    link
  end

  defp ask!(as, user, body \\ %{}) do
    as.(user)
    |> send_json(:post, "/api/me/support-requests", body)
    |> json_response(201)
    |> Map.fetch!("support_request")
  end

  test "invite, accept, quiet leave; strangers and a third buddy are refused", ctx do
    %{as: as, member: member, dimitra: dimitra, kostas: kostas, coach: coach} = ctx

    assert %{"candidates" => candidates} =
             as.(member) |> get("/api/me/buddies/candidates") |> json_response(200)

    assert [%{"relation" => "coach", "person" => %{"id" => coach_id}}] = candidates
    assert coach_id == coach.id

    assert %{"candidates" => found} =
             as.(member)
             |> get("/api/me/buddies/candidates?q=#{String.slice(dimitra.nickname, 0, 6)}")
             |> json_response(200)

    assert Enum.any?(found, &(&1["person"]["id"] == dimitra.id and &1["relation"] == "club"))

    link = invite!(as, member, dimitra)
    assert %{"status" => "pending", "role" => "requester", "expires_at" => expires} = link
    assert expires
    assert [%{payload: %{"link_id" => link_id}}] = notifications(dimitra, :buddy_invite)
    assert link_id == link["id"]

    assert %{"invitations" => [%{"id" => ^link_id, "role" => "buddy"}]} =
             as.(dimitra) |> get("/api/me/buddies") |> json_response(200)

    assert %{"link" => %{"status" => "active"}} =
             as.(dimitra) |> post("/api/me/buddies/#{link_id}/accept") |> json_response(200)

    assert [_accepted] = notifications(member, :buddy_accepted)

    assert as.(member) |> post("/api/me/buddies/#{link_id}/accept") |> response(403)

    assert %{"code" => "not_eligible_for_buddy"} =
             as.(member)
             |> send_json(:post, "/api/me/buddies", %{user_id: ctx.stranger.id})
             |> json_response(403)

    assert %{"code" => "cannot_buddy_self"} =
             as.(member)
             |> send_json(:post, "/api/me/buddies", %{user_id: member.id})
             |> json_response(422)

    assert %{"code" => "buddy_already_invited"} =
             as.(member)
             |> send_json(:post, "/api/me/buddies", %{user_id: dimitra.id})
             |> json_response(409)

    _second = invite!(as, member, kostas)

    assert %{"code" => "buddy_limit_reached"} =
             as.(member)
             |> post("/api/me/buddies/invite-links")
             |> json_response(409)

    assert %{"link" => %{"receives_weekly_summary" => true}} =
             as.(member)
             |> send_json(:patch, "/api/me/buddies/#{link_id}", %{receives_weekly_summary: true})
             |> json_response(200)

    assert as.(dimitra)
           |> send_json(:patch, "/api/me/buddies/#{link_id}", %{receives_weekly_summary: false})
           |> json_response(403)

    before = length(Repo.all(Notification))

    assert %{"link" => %{"status" => "ended", "ended_by_me" => true}} =
             as.(dimitra) |> post("/api/me/buddies/#{link_id}/leave") |> json_response(200)

    assert length(Repo.all(Notification)) == before

    assert %{"buddies" => buddies} = as.(member) |> get("/api/me/buddies") |> json_response(200)

    assert %{"status" => "ended", "ended_by_me" => false} =
             Enum.find(buddies, &(&1["id"] == link_id))

    assert as.(ctx.stranger) |> post("/api/me/buddies/#{link_id}/leave") |> json_response(404)
  end

  test "an off-platform invite link: public preview, claim when signed in", ctx do
    %{as: as, member: member, stranger: outsider} = ctx

    assert %{"token" => token, "url" => url, "path" => path, "link" => %{"person" => nil}} =
             as.(member) |> post("/api/me/buddies/invite-links") |> json_response(201)

    assert String.ends_with?(url, path)

    assert %{"status" => "pending", "inviter" => %{"id" => inviter_id}} =
             build_conn() |> get("/api/buddy-invites/#{token}") |> json_response(200)

    assert inviter_id == member.id
    assert build_conn() |> post("/api/me/buddy-invites/#{token}/claim") |> response(401)

    assert %{"code" => "buddy_invite_unavailable"} =
             as.(member) |> post("/api/me/buddy-invites/#{token}/claim") |> json_response(409)

    assert %{
             "link" => %{
               "status" => "active",
               "role" => "buddy",
               "person" => %{"id" => ^inviter_id}
             }
           } =
             as.(outsider) |> post("/api/me/buddy-invites/#{token}/claim") |> json_response(200)

    assert [_] = notifications(member, :buddy_accepted)

    assert %{"status" => "unavailable", "inviter" => nil} =
             build_conn() |> get("/api/buddy-invites/#{token}") |> json_response(200)

    assert build_conn()
           |> get("/api/buddy-invites/#{String.duplicate("a", 43)}")
           |> json_response(404)
  end

  test "support request: undo window, delivery, reply opens the conversation", ctx do
    %{as: as, member: member, dimitra: dimitra} = ctx

    assert %{"code" => "no_active_buddies"} =
             as.(member)
             |> send_json(:post, "/api/me/support-requests", %{})
             |> json_response(409)

    buddies!(as, member, dimitra)

    request = ask!(as, member, %{message: "Δύσκολο βράδυ."})

    assert %{"status" => "sending", "can_undo" => true, "role" => "sender", "source" => "quick"} =
             request

    assert [%{"person" => %{"id" => dimitra_id}, "quiet_hours" => false}] = request["recipients"]
    assert dimitra_id == dimitra.id

    # Not told yet: the buddy cannot see it during the undo window.
    assert as.(dimitra) |> get("/api/me/support-requests/#{request["id"]}") |> json_response(404)

    :ok = SupportRequests.deliver(member.id, request["id"])
    :ok = SupportRequests.deliver(member.id, request["id"])

    assert [%{payload: payload}] = notifications(dimitra, :support_request)
    assert payload["quick_replies"] == ["here", "walk", "call"]
    assert payload["message"] == "Δύσκολο βράδυ."
    refute Map.has_key?(payload, "source")

    assert %{"code" => "undo_window_passed"} =
             as.(member)
             |> post("/api/me/support-requests/#{request["id"]}/undo")
             |> json_response(409)

    assert %{"support_request" => seen} =
             as.(dimitra)
             |> get("/api/me/support-requests/#{request["id"]}")
             |> json_response(200)

    assert %{"role" => "buddy", "message" => "Δύσκολο βράδυ.", "sender" => %{"id" => _}} = seen
    refute Map.has_key?(seen, "source")
    refute Map.has_key?(seen, "recipients")

    assert %{"support_requests" => [%{"id" => _}]} =
             as.(dimitra) |> get("/api/me/support-requests?role=received") |> json_response(200)

    assert %{"reply" => reply, "sender_phone" => nil} =
             as.(dimitra)
             |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
               kind: "walk",
               text: "Πάμε μια βόλτα στις 10;"
             })
             |> json_response(201)

    assert %{"kind" => "walk", "conversation" => %{"thread_id" => thread_id}} = reply

    assert [%{body: "Πάμε μια βόλτα στις 10;"}] =
             Repo.all(from(m in Message, where: m.thread_id == ^thread_id))

    assert [%{payload: %{"kind" => "walk"}}] = notifications(member, :support_reply)

    assert %{
             "support_request" => %{
               "replies" => [_],
               "recipients" => [%{"replied_at" => replied}]
             }
           } =
             as.(member) |> get("/api/me/support-requests/#{request["id"]}") |> json_response(200)

    assert replied

    # A quick reply without words reuses the same conversation.
    assert %{"reply" => %{"conversation" => %{"thread_id" => ^thread_id}}} =
             as.(dimitra)
             |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
               kind: "here"
             })
             |> json_response(201)

    assert as.(ctx.kostas)
           |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
             kind: "here"
           })
           |> json_response(404)
  end

  test "undo within five seconds: nobody is told", ctx do
    %{as: as, member: member, dimitra: dimitra} = ctx
    buddies!(as, member, dimitra)
    request = ask!(as, member)

    assert %{"support_request" => %{"status" => "undone", "can_undo" => false}} =
             as.(member)
             |> post("/api/me/support-requests/#{request["id"]}/undo")
             |> json_response(200)

    :ok = SupportRequests.deliver(member.id, request["id"])
    assert notifications(dimitra, :support_request) == []

    assert %{"code" => "already_undone"} =
             as.(member)
             |> post("/api/me/support-requests/#{request["id"]}/undo")
             |> json_response(409)
  end

  test "quiet hours deliver silently and tell the sender; the phone only when shared", ctx do
    %{as: as, member: member, dimitra: dimitra} = ctx
    buddies!(as, member, dimitra)

    now = DateTime.utc_now()
    from = now |> DateTime.add(-3600, :second) |> DateTime.to_time() |> Calendar.strftime("%H:%M")
    to = now |> DateTime.add(3600, :second) |> DateTime.to_time() |> Calendar.strftime("%H:%M")

    assert %{"settings" => %{"quiet_hours" => %{"from" => ^from}}} =
             as.(dimitra)
             |> send_json(:put, "/api/me/buddies/settings", %{
               quiet_hours: %{from: from, to: to},
               tz: "Etc/UTC"
             })
             |> json_response(200)

    request = ask!(as, member)
    assert [%{"id" => dimitra_id}] = request["quiet_hours"]
    assert dimitra_id == dimitra.id

    :ok = SupportRequests.deliver(member.id, request["id"])
    assert [%{payload: %{"silent" => true}}] = notifications(dimitra, :support_request)

    assert %{"sender_phone" => nil} =
             as.(dimitra)
             |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
               kind: "call"
             })
             |> json_response(201)

    assert %{"code" => "phone_required"} =
             as.(member)
             |> send_json(:put, "/api/me/buddies/settings", %{share_phone: true})
             |> json_response(422)

    assert %{"settings" => %{"share_phone" => true}} =
             as.(member)
             |> send_json(:put, "/api/me/buddies/settings", %{
               share_phone: true,
               phone: "+30 690 123 4567"
             })
             |> json_response(200)

    assert %{"sender_phone" => "+30 690 123 4567"} =
             as.(dimitra)
             |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
               kind: "call"
             })
             |> json_response(201)

    assert %{"sender_phone" => nil} =
             as.(dimitra)
             |> send_json(:post, "/api/me/support-requests/#{request["id"]}/replies", %{
               kind: "here"
             })
             |> json_response(201)
  end

  test "a few requests an hour; the calm card after ten minutes, once", ctx do
    %{as: as, member: member, dimitra: dimitra} = ctx
    buddies!(as, member, dimitra)

    first = ask!(as, member)
    _ = ask!(as, member)
    _ = ask!(as, member)

    assert %{"code" => "support_rate_limited"} =
             as.(member)
             |> send_json(:post, "/api/me/support-requests", %{})
             |> json_response(429)

    :ok = SupportRequests.deliver(member.id, first["id"])
    later = DateTime.add(DateTime.utc_now(), 11 * 60, :second)

    :ok =
      SupportRequests.nudge(member.id, first["id"], DateTime.add(DateTime.utc_now(), 60, :second))

    assert notifications(member, :support_no_reply_nudge) == []

    :ok = SupportRequests.nudge(member.id, first["id"], later)
    :ok = SupportRequests.nudge(member.id, first["id"], later)
    assert [_once] = notifications(member, :support_no_reply_nudge)
  end

  test "the weekly summary goes only to buddies who get it, counts only", ctx do
    %{as: as, member: member, dimitra: dimitra, kostas: kostas} = ctx
    link = buddies!(as, member, dimitra)
    buddies!(as, member, kostas)

    as.(member)
    |> send_json(:patch, "/api/me/buddies/#{link["id"]}", %{receives_weekly_summary: true})
    |> json_response(200)

    as.(member)
    |> put("/api/me/body/consents/health_data")
    |> json_response(200)

    as.(member)
    |> send_json(:post, "/api/me/wellness/cravings", %{
      intensity: 8,
      triggers: ["stress"],
      outcome: "resisted",
      note: "chips at night"
    })
    |> json_response(201)

    request = ask!(as, member)
    :ok = SupportRequests.deliver(member.id, request["id"])

    now = DateTime.utc_now()
    :ok = BuddyWeeklySummaries.send_for(member.id, "Etc/UTC", now)
    :ok = BuddyWeeklySummaries.send_for(member.id, "Etc/UTC", now)

    assert [%{payload: payload}] = notifications(dimitra, :buddy_weekly_summary)
    assert notifications(kostas, :buddy_weekly_summary) == []
    assert %{"hard_moments" => 1, "overcome" => 1, "support_requests" => 1} = payload

    flat = inspect(payload)
    for leak <- ["chips", "stress", "intensity", "occurred"], do: refute(flat =~ leak)
  end

  test "the coach summary needs the member's grant; cravings only with the second", ctx do
    %{as: as, member: member, coach: coach, gym: gym} = ctx

    path =
      "/api/org/#{gym.slug}/staff/clients/#{member.id}/wellness-summary?week=#{Date.utc_today()}"

    as.(member)
    |> put("/api/me/body/consents/health_data")
    |> json_response(200)

    as.(member)
    |> send_json(:post, "/api/me/wellness/cravings", %{
      intensity: 7,
      triggers: ["boredom"],
      note: "sweets"
    })
    |> json_response(201)

    as.(member)
    |> send_json(:post, "/api/me/wellness/entries", %{kind: "water", value: %{ml: 2500}})
    |> json_response(201)

    assert %{"shared" => false, "summary" => nil} = as.(coach) |> get(path) |> json_response(200)

    assert %{"sharing" => %{"wellness" => true, "cravings" => false}} =
             as.(member)
             |> send_json(:put, "/api/me/wellness-summary-sharing", %{wellness: true})
             |> json_response(200)

    assert %{"shared" => true, "summary" => summary} =
             as.(coach) |> get(path) |> json_response(200)

    assert %{"water" => %{"days_on_goal" => 1}, "cravings" => nil} = summary

    as.(member)
    |> send_json(:put, "/api/me/wellness-summary-sharing", %{cravings: true})
    |> json_response(200)

    assert %{"summary" => %{"cravings" => %{"count" => 1, "moments" => [%{"time" => _}]}} = body} =
             as.(coach) |> get(path) |> json_response(200)

    refute inspect(body) =~ "sweets"
    refute inspect(body) =~ "boredom"

    # Another member of the gym, not a coach: no access.
    assert as.(ctx.dimitra) |> get(path) |> response(403)

    assert %{"sharing" => %{"wellness" => false, "cravings" => false}} =
             as.(member)
             |> send_json(:put, "/api/me/wellness-summary-sharing", %{wellness: false})
             |> json_response(200)

    assert %{"shared" => false} = as.(coach) |> get(path) |> json_response(200)
  end
end
