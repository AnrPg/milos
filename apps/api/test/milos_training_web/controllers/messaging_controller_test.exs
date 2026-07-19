defmodule MilosTrainingWeb.MessagingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  describe "POST /api/threads (direct)" do
    test "admin can create a direct thread with an athlete", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      response =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      assert response["thread"]["context_type"] == "direct"
      assert length(response["thread"]["participants"]) == 2
    end

    test "calling twice returns the same thread", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      r1 =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      r2 =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      assert r1["thread"]["id"] == r2["thread"]["id"]
    end

    test "rejects self conversations", %{conn: conn} do
      member = user_fixture()

      conn
      |> put_bearer_token(member)
      |> post("/api/threads", %{context_type: "direct", participant_id: member.id})
      |> json_response(422)
    end
  end

  describe "POST /api/threads (contextual authorization)" do
    test "foreign users cannot create or join an assignment thread", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      outsider = user_fixture(%{role: :athlete})
      workout = workout_fixture(admin)

      {:ok, assignment} =
        MilosTraining.Workouts.assign_workout(%{
          master_workout_id: workout.id,
          athlete_ids: [athlete.id],
          scheduled_for: Date.utc_today()
        })

      conn
      |> put_bearer_token(outsider)
      |> post("/api/threads", %{context_type: "assignment", context_id: assignment.id})
      |> json_response(403)

      response =
        conn
        |> put_bearer_token(athlete)
        |> post("/api/threads", %{context_type: "assignment", context_id: assignment.id})
        |> json_response(200)

      participant_ids = Enum.map(response["thread"]["participants"], & &1["user_id"])
      assert athlete.id in participant_ids
      assert admin.id in participant_ids

      conn
      |> put_bearer_token(outsider)
      |> post("/api/threads", %{context_type: "assignment", context_id: assignment.id})
      |> json_response(403)
    end

    test "foreign users cannot create or join a class thread", %{conn: conn} do
      admin = admin_fixture()
      member = user_fixture()
      outsider = user_fixture()
      workout = workout_fixture(admin)
      slot = slot_fixture(workout, %{auto_approve: true})
      {:ok, _booking} = MilosTraining.Scheduling.submit_auto_approved_booking(member.id, slot.id)

      conn
      |> put_bearer_token(outsider)
      |> post("/api/threads", %{context_type: "class_slot", context_id: slot.id})
      |> json_response(403)

      response =
        conn
        |> put_bearer_token(member)
        |> post("/api/threads", %{context_type: "class_slot", context_id: slot.id})
        |> json_response(200)

      participant_ids = Enum.map(response["thread"]["participants"], & &1["user_id"])
      assert member.id in participant_ids
      assert admin.id in participant_ids
    end
  end

  describe "GET /api/threads" do
    test "returns threads for the current user", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      conn
      |> put_bearer_token(admin)
      |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
      |> json_response(200)

      response =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads")
        |> json_response(200)

      assert length(response["threads"]) == 1
    end

    test "can filter by context_type", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      conn
      |> put_bearer_token(admin)
      |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
      |> json_response(200)

      response =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads?context_type=direct")
        |> json_response(200)

      assert length(response["threads"]) == 1

      empty =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads?context_type=assignment")
        |> json_response(200)

      assert empty["threads"] == []
    end
  end

  describe "GET /api/threads/unread-count" do
    test "counts only incoming unread thread activity", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      %{"message" => own_message} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{body: "Outbound only"})
        |> json_response(201)

      own_unread =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads/unread-count")
        |> json_response(200)

      assert own_unread["unread_count"] == 0

      %{"message" => incoming_message} =
        conn
        |> put_bearer_token(athlete)
        |> post("/api/threads/#{thread["id"]}/messages", %{body: "Incoming"})
        |> json_response(201)

      incoming_unread =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads/unread-count")
        |> json_response(200)

      assert incoming_unread["unread_count"] == 1

      conn
      |> put_bearer_token(admin)
      |> post("/api/threads/#{thread["id"]}/read", %{message_id: incoming_message["id"]})
      |> json_response(200)

      conn
      |> put_bearer_token(admin)
      |> post("/api/threads/#{thread["id"]}/messages", %{body: "Reply after reading"})
      |> json_response(201)

      read_unread =
        conn
        |> put_bearer_token(admin)
        |> get("/api/threads/unread-count")
        |> json_response(200)

      assert own_message["sender_id"] == admin.id
      assert read_unread["unread_count"] == 0
    end
  end

  describe "POST /api/threads/:id/messages" do
    test "sends a message in a thread", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      response =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{
          body: "Great session today!",
          message_type: "chat"
        })
        |> json_response(201)

      assert response["message"]["body"] == "Great session today!"
      assert response["message"]["message_type"] == "chat"
      assert response["message"]["sender_id"] == admin.id
    end

    test "replays a client operation without duplicating the message", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      operation_id = Ecto.UUID.generate()

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      payload = %{
        body: "Persist this once",
        message_type: "chat",
        client_operation_id: operation_id
      }

      first =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", payload)
        |> json_response(201)

      replay =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", payload)
        |> json_response(201)

      assert replay["message"]["id"] == first["message"]["id"]
      assert replay["message"]["client_operation_id"] == operation_id
      assert MilosTraining.Repo.aggregate(Oban.Job, :count) == 1

      assert 1 ==
               MilosTraining.Repo.aggregate(
                 from(message in MilosTraining.Messaging.Message,
                   where:
                     message.sender_id == ^admin.id and
                       message.client_operation_id == ^operation_id
                 ),
                 :count
               )
    end

    test "admin can send a coaching_note", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      response =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{
          body: "Focus on your form this week.",
          message_type: "coaching_note"
        })
        |> json_response(201)

      assert response["message"]["message_type"] == "coaching_note"
    end

    test "non-participant cannot send a message", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      outsider = admin_fixture()

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      conn
      |> put_bearer_token(outsider)
      |> post("/api/threads/#{thread["id"]}/messages", %{body: "Intruder!"})
      |> json_response(403)
    end
  end

  describe "GET /api/threads/:id/messages" do
    test "returns messages in a thread", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      conn
      |> put_bearer_token(admin)
      |> post("/api/threads/#{thread["id"]}/messages", %{body: "Hello!"})
      |> json_response(201)

      response =
        conn
        |> put_bearer_token(athlete)
        |> get("/api/threads/#{thread["id"]}/messages")
        |> json_response(200)

      assert length(response["messages"]) == 1
      assert hd(response["messages"])["body"] == "Hello!"
    end

    test "uses a bounded opaque message cursor and rejects malformed pagination", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      other = user_fixture()

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      %{"thread" => other_thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: other.id})
        |> json_response(200)

      messages =
        for body <- ["one", "two", "three"] do
          conn
          |> put_bearer_token(admin)
          |> post("/api/threads/#{thread["id"]}/messages", %{body: body})
          |> json_response(201)
          |> get_in(["message"])
        end

      %{"message" => foreign} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{other_thread["id"]}/messages", %{body: "foreign"})
        |> json_response(201)

      page =
        conn
        |> put_bearer_token(athlete)
        |> get(
          "/api/threads/#{thread["id"]}/messages?limit=1&before_id=#{List.last(messages)["id"]}"
        )
        |> json_response(200)

      assert Enum.map(page["messages"], & &1["body"]) == ["two"]

      for query <- [
            "limit=invalid",
            "limit=0",
            "limit=101",
            "before_id=not-a-uuid",
            "before_id=#{foreign["id"]}"
          ] do
        conn
        |> put_bearer_token(athlete)
        |> get("/api/threads/#{thread["id"]}/messages?#{query}")
        |> json_response(400)
      end
    end
  end

  describe "POST /api/threads/:id/read" do
    test "marks a message as read", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      %{"message" => message} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{body: "Read me!"})
        |> json_response(201)

      conn
      |> put_bearer_token(athlete)
      |> post("/api/threads/#{thread["id"]}/read", %{message_id: message["id"]})
      |> json_response(200)
      |> then(&assert &1 == %{"message_id" => message["id"], "read" => true})
    end

    test "rejects a read pointer from another thread and never moves backward", %{conn: conn} do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      other = user_fixture()

      %{"thread" => thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: athlete.id})
        |> json_response(200)

      %{"thread" => other_thread} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads", %{context_type: "direct", participant_id: other.id})
        |> json_response(200)

      %{"message" => older} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{body: "older"})
        |> json_response(201)

      %{"message" => newer} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{thread["id"]}/messages", %{body: "newer"})
        |> json_response(201)

      %{"message" => foreign} =
        conn
        |> put_bearer_token(admin)
        |> post("/api/threads/#{other_thread["id"]}/messages", %{body: "foreign"})
        |> json_response(201)

      conn
      |> put_bearer_token(athlete)
      |> post("/api/threads/#{thread["id"]}/read", %{message_id: foreign["id"]})
      |> json_response(422)

      conn
      |> put_bearer_token(athlete)
      |> post("/api/threads/#{thread["id"]}/read", %{message_id: newer["id"]})
      |> json_response(200)

      response =
        conn
        |> put_bearer_token(athlete)
        |> post("/api/threads/#{thread["id"]}/read", %{message_id: older["id"]})
        |> json_response(200)

      assert response == %{"message_id" => newer["id"], "read" => true}
    end
  end
end
