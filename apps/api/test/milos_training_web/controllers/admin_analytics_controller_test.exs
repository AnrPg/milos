defmodule MilosTrainingWeb.AdminAnalyticsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Analytics

  import MilosTraining.TestFixtures

  test "admin can fetch analytics summary backed by persisted facts", %{conn: conn} do
    admin = admin_fixture()

    {:ok, _event} =
      Analytics.record_event(%{
        event_name: "payment_recorded",
        user_id: admin.id,
        context_type: "membership_payment"
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> get("/api/admin/analytics/summary", %{days: 30})
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
