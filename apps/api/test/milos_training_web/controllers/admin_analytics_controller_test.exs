defmodule MilosTrainingWeb.AdminAnalyticsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Analytics, Organizations, Repo}

  import MilosTraining.TestFixtures

  test "admin can fetch analytics summary backed by persisted facts", %{conn: conn} do
    admin = admin_fixture()

    {:ok, organization} = Organizations.create_organization(%{name: "Analytics Summary Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

    {:ok, _event} =
      Analytics.record_event(%{
        event_name: "payment_recorded",
        user_id: admin.id,
        context_type: "membership_payment"
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> get(
        "/api/org/#{organization.slug}/admin/analytics/summary",
        %{days: 30}
      )
      |> json_response(200)

    assert response["analytics"]["events"]["by_name"]["payment_recorded"] >= 1
    assert is_map(response["finance"])
    assert is_map(response["feedback"])
    assert is_map(response["wellbeing"])
    assert is_map(response["coaching"])
    assert is_integer(response["coaching"]["active_athlete_count"])
    assert is_map(response["dashboard"]["cross_context"])
  end
end
