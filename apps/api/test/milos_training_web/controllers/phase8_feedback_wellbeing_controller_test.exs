defmodule MilosTrainingWeb.Phase8FeedbackWellbeingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  test "user can submit and list reviews", %{conn: conn} do
    user = user_fixture(%{role: :athlete})

    create_response =
      conn
      |> put_bearer_token(user)
      |> post("/api/reviews", %{
        target_type: "general",
        rating: 5,
        sentiment: "positive",
        body: "Great pacing.",
        answers: [
          %{
            question_key: "difficulty",
            question_text: "How did the difficulty fit?",
            answer_text: "Right level",
            rating_value: 5
          }
        ]
      })
      |> json_response(201)

    assert create_response["review"]["rating"] == 5
    assert [%{"question_key" => "difficulty"}] = create_response["review"]["answers"]

    list_response =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> get("/api/reviews")
      |> json_response(200)

    assert Enum.map(list_response["reviews"], & &1["id"]) == [create_response["review"]["id"]]
  end

  test "user can report and heal own injury but cannot heal another user's report", %{conn: conn} do
    user = user_fixture(%{role: :member})
    other_user = user_fixture(%{role: :member})

    create_response =
      conn
      |> put_bearer_token(user)
      |> post("/api/wellbeing/injuries", %{
        body_area: "knee",
        severity: "mild",
        training_limitations: "Avoid box jumps"
      })
      |> json_response(201)

    injury_id = create_response["injury"]["id"]
    assert create_response["injury"]["status"] == "active"

    conn
    |> recycle()
    |> put_bearer_token(other_user)
    |> patch("/api/wellbeing/injuries/#{injury_id}/heal", %{})
    |> json_response(404)

    heal_response =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> patch("/api/wellbeing/injuries/#{injury_id}/heal", %{})
      |> json_response(200)

    assert heal_response["injury"]["status"] == "healed"
  end

  test "public injury reporting rejects protected visibility fields", %{conn: conn} do
    user = user_fixture(%{role: :member})

    conn
    |> put_bearer_token(user)
    |> post("/api/wellbeing/injuries", %{
      body_area: "shoulder",
      severity: "mild",
      visibility: "admin_only"
    })
    |> json_response(422)
  end

  test "admin-only injuries are hidden from the affected user's list and self-heal action", %{
    conn: conn
  } do
    admin = admin_fixture()
    user = user_fixture(%{role: :athlete})

    create_response =
      conn
      |> put_bearer_token(admin)
      |> post("/api/admin/wellbeing/users/#{user.id}/injuries", %{
        body_area: "back",
        severity: "moderate",
        training_limitations: "Coach-managed limitation",
        visibility: "admin_only"
      })
      |> json_response(201)

    injury_id = create_response["injury"]["id"]
    assert create_response["injury"]["visibility"] == "admin_only"

    list_response =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> get("/api/wellbeing/injuries")
      |> json_response(200)

    refute Enum.any?(list_response["injuries"], &(&1["id"] == injury_id))

    conn
    |> recycle()
    |> put_bearer_token(user)
    |> patch("/api/wellbeing/injuries/#{injury_id}/heal", %{})
    |> json_response(404)

    admin_heal_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/wellbeing/injuries/#{injury_id}/heal", %{})
      |> json_response(200)

    assert admin_heal_response["injury"]["status"] == "healed"
  end
end
