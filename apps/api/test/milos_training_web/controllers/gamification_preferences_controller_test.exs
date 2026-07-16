defmodule MilosTrainingWeb.GamificationPreferencesControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

  alias MilosTraining.TestFixtures

  describe "GET /api/gamification/preferences" do
    test "returns empty off-days when preferences have not been saved", %{conn: conn} do
      user = TestFixtures.user_fixture()

      conn =
        conn
        |> put_bearer_token(user)
        |> get(~p"/api/gamification/preferences")

      assert %{"preferences" => %{"off_days" => []}} = json_response(conn, 200)
    end
  end

  describe "PUT /api/gamification/preferences" do
    test "persists off-days for the current user", %{conn: conn} do
      user = TestFixtures.user_fixture()

      conn =
        conn
        |> put_bearer_token(user)
        |> put(~p"/api/gamification/preferences", %{"off_days" => [0, 6]})

      assert %{"preferences" => %{"off_days" => [0, 6]}} = json_response(conn, 200)
    end

    test "allows up to five off-days", %{conn: conn} do
      user = TestFixtures.user_fixture()

      conn =
        conn
        |> put_bearer_token(user)
        |> put(~p"/api/gamification/preferences", %{"off_days" => [0, 2, 3, 4, 6]})

      assert %{"preferences" => %{"off_days" => [0, 2, 3, 4, 6]}} = json_response(conn, 200)
    end
  end
end
