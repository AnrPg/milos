defmodule MilosTrainingWeb.CheckInControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  test "submit, list and delete the current user's check-ins", %{conn: conn} do
    user = user_fixture(%{role: :member})

    created =
      conn
      |> put_bearer_token(user)
      |> post("/api/wellbeing/check-ins", %{
        answers: [
          %{question_key: "mood", value: 3, note: "ok"},
          %{question_key: "sleep", value: 2}
        ]
      })
      |> json_response(201)

    assert %{
             "journal_visibility" => "private",
             "answers" => [
               %{"question_key" => "sleep", "value" => 2, "note" => nil},
               %{"question_key" => "mood", "value" => 3, "note" => "ok"}
             ]
           } = created["check_in"]

    listed =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> get("/api/wellbeing/check-ins")
      |> json_response(200)

    assert [%{"key" => "sleep", "min" => 1, "max" => 4} | _rest] = listed["questions"]
    assert [%{"id" => id}] = listed["check_ins"]
    assert id == created["check_in"]["id"]

    conn
    |> recycle()
    |> put_bearer_token(user)
    |> delete("/api/wellbeing/check-ins/#{id}")
    |> response(204)

    assert %{"check_ins" => []} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> get("/api/wellbeing/check-ins")
             |> json_response(200)
  end

  test "a submission needs at least one answer on the 1–4 scale", %{conn: conn} do
    user = user_fixture(%{role: :member})

    for answers <- [[], [%{question_key: "mood", value: 5}]] do
      conn
      |> put_bearer_token(user)
      |> post("/api/wellbeing/check-ins", %{answers: answers})
      |> json_response(422)
    end
  end
end
