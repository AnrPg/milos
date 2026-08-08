defmodule MilosTrainingWeb.MyFinanceControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  describe "GET /api/org/:organization_slug/me/entitlement" do
    test "returns an empty entitlement for users without a finance profile", %{conn: conn} do
      user = user_fixture(%{role: :member})

      response =
        conn
        |> put_bearer_token(user)
        |> get(
          "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/me/entitlement"
        )
        |> json_response(200)

      assert response == %{"entitlement" => nil}
    end

    test "does not expose the tenant finance summary on the global personal route", %{conn: conn} do
      user = user_fixture(%{role: :member})

      assert_error_sent 404, fn ->
        conn
        |> put_bearer_token(user)
        |> get("/api/me/finance")
      end
    end
  end
end
