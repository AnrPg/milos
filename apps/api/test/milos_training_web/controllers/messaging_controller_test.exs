defmodule MilosTrainingWeb.MessagingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

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
    end
  end
end
