defmodule MilosTrainingWeb.MyFinanceControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations

  describe "GET /api/org/:organization_slug/me/entitlement" do
    test "returns an empty entitlement for users without a finance profile", %{conn: conn} do
      user = user_fixture(%{role: :member})
      {:ok, organization} = Organizations.create_organization(%{name: "My Finance Test Gym"})

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      response =
        conn
        |> put_bearer_token(user)
        |> get("/api/org/#{organization.slug}/me/entitlement")
        |> json_response(200)

      assert response == %{"entitlement" => nil}
    end

    test "does not expose the tenant finance summary on the global personal route", %{conn: conn} do
      user = user_fixture(%{role: :member})

      response =
        conn
        |> put_bearer_token(user)
        |> get("/api/me/finance")

      assert response.status == 404
    end
  end
end
