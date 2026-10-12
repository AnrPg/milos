defmodule MilosTrainingWeb.CoachingExtrasControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Finance, Notifications, Organizations, Repo}
  alias MilosTraining.Workers.CoachingReplyOverdueJob

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    coach = user_fixture()
    {:ok, membership} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    # A head coach reaches every client; own-client scope has its own test.
    {:ok, _} =
      MilosTraining.Organizations.OrganizationStore.update_membership_settings(
        organization.id,
        membership.id,
        %{coach_scope: :all}
      )

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{
      organization: organization,
      coach: coach,
      coach_conn: put_bearer_token(conn, coach),
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp client(conn, fields) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, package} =
      Finance.create_package(%{
        name: "Coaching #{System.unique_integer([:positive])}",
        package_type: "membership",
        fields: fields
      })

    {:ok, _} = Finance.assign_package(membership.id, package.id, %{})
    {user, put_bearer_token(conn, user)}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  @coaching %{"online_coaching.included" => true}

  test "form reviews reserve a unit, are reviewed by coaches and can be withdrawn", %{
    conn: conn,
    coach_conn: coach_conn,
    base: base
  } do
    {user, client_conn} =
      client(
        conn,
        Map.put(@coaching, "online_coaching.form_reviews", %{
          "limit" => 1,
          "period" => "calendar_month"
        })
      )

    submit = fn body -> client_conn |> send_json(:post, "#{base}/me/form-reviews", body) end

    assert %{"errors" => _} = submit.(%{video_url: "ftp://bad"}) |> json_response(422)

    first =
      submit.(%{video_url: "https://youtu.be/squat", exercise_name: "Back squat"})
      |> json_response(201)
      |> Map.fetch!("form_review")

    assert %{"code" => "finance_allowance_exhausted"} =
             submit.(%{video_url: "https://youtu.be/second"}) |> json_response(409)

    client_conn
    |> send_json(:post, "#{base}/me/form-reviews/#{first["id"]}/withdraw", %{})
    |> json_response(200)

    second =
      submit.(%{video_url: "https://youtu.be/again", note: "Knees?"})
      |> json_response(201)
      |> Map.fetch!("form_review")

    assert [%{"id" => queued_id, "nickname" => nickname}] =
             coach_conn
             |> recycle()
             |> get("#{base}/staff/form-reviews")
             |> json_response(200)
             |> Map.fetch!("form_reviews")

    assert queued_id == second["id"]
    assert nickname == user.nickname

    reviewed =
      coach_conn
      |> send_json(:post, "#{base}/staff/form-reviews/#{second["id"]}/review", %{
        feedback: "Keep your chest up."
      })
      |> json_response(200)
      |> Map.fetch!("form_review")

    assert reviewed["status"] == "reviewed"

    assert %{"code" => "form_review_closed"} =
             client_conn
             |> send_json(:post, "#{base}/me/form-reviews/#{second["id"]}/withdraw", %{})
             |> json_response(409)

    assert Enum.any?(Notifications.list_for_user(user.id), &(&1.type == "form_review_completed"))

    {_outsider, outsider_conn} = client(conn, %{})

    assert outsider_conn
           |> send_json(:post, "#{base}/me/form-reviews", %{video_url: "https://youtu.be/x"})
           |> json_response(403)
  end

  test "clients cannot send coaching notes, and late replies reach staff once", %{
    conn: conn,
    coach: coach,
    coach_conn: coach_conn,
    base: base,
    organization: organization
  } do
    {client_user, client_conn} =
      client(conn, Map.put(@coaching, "online_coaching.response_sla_hours", 24))

    thread =
      client_conn
      |> send_json(:post, "#{base}/me/threads", %{
        context_type: "direct",
        participant_id: coach.id
      })
      |> json_response(200)
      |> Map.fetch!("thread")

    message =
      client_conn
      |> send_json(:post, "#{base}/me/threads/#{thread["id"]}/messages", %{
        body: "Is my program ok?",
        message_type: "coaching_note"
      })
      |> json_response(201)
      |> Map.fetch!("message")

    assert message["message_type"] == "chat"

    Repo.query!(
      "UPDATE messaging_messages SET inserted_at = inserted_at - interval '2 days' WHERE id = $1",
      [Ecto.UUID.dump!(message["id"])]
    )

    [item] =
      coach_conn
      |> recycle()
      |> get("#{base}/staff/reply-queue")
      |> json_response(200)
      |> Map.fetch!("replies")

    assert item["client_id"] == client_user.id
    assert item["response_sla_hours"] == 24
    assert item["overdue"]

    CoachingReplyOverdueJob.alert(organization.id, DateTime.utc_now())
    CoachingReplyOverdueJob.alert(organization.id, DateTime.utc_now())

    alerts =
      Enum.filter(Notifications.list_for_user(coach.id), &(&1.type == "coaching_reply_overdue"))

    assert length(alerts) == 1

    coach_conn
    |> send_json(:post, "#{base}/me/threads/#{thread["id"]}/messages", %{body: "Looks good!"})
    |> json_response(201)

    assert %{"replies" => []} =
             coach_conn |> recycle() |> get("#{base}/staff/reply-queue") |> json_response(200)
  end

  test "staff write nutrition plans that clients with the benefit can read", %{
    conn: conn,
    coach_conn: coach_conn,
    base: base
  } do
    {client_user, client_conn} = client(conn, %{"online_coaching.nutrition_plan" => true})

    assert %{"nutrition_plan" => nil} =
             client_conn |> recycle() |> get("#{base}/me/nutrition-plan") |> json_response(200)

    coach_conn
    |> send_json(:put, "#{base}/staff/clients/#{client_user.id}/nutrition-plan", %{
      title: "Cutting phase",
      body: "High protein, moderate carbs.",
      daily_calories: 2200,
      protein_grams: 180
    })
    |> json_response(200)

    assert %{"nutrition_plan" => %{"title" => "Cutting phase", "daily_calories" => 2200}} =
             client_conn |> recycle() |> get("#{base}/me/nutrition-plan") |> json_response(200)

    assert Enum.any?(
             Notifications.list_for_user(client_user.id),
             &(&1.type == "nutrition_plan_updated")
           )

    {_plain, plain_conn} = client(conn, %{})
    assert plain_conn |> recycle() |> get("#{base}/me/nutrition-plan") |> json_response(403)

    stranger = user_fixture()

    assert coach_conn
           |> send_json(:put, "#{base}/staff/clients/#{stranger.id}/nutrition-plan", %{
             title: "Nope",
             body: "Not a client"
           })
           |> json_response(404)
  end
end
