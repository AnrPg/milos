defmodule MilosTrainingWeb.MyFinanceControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  describe "GET /api/me/entitlement" do
    test "returns an empty entitlement for users without a finance profile", %{conn: conn} do
      user = user_fixture(%{role: :member})

      response =
        conn
        |> put_bearer_token(user)
        |> get("/api/me/entitlement")
        |> json_response(200)

      assert response == %{"entitlement" => nil}
    end
  end
end
