defmodule MilosTrainingWeb.AppointmentsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Finance, Notifications, Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{
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
        name: "PT #{System.unique_integer([:positive])}",
        package_type: "pt_pack",
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

  defp slot(coach_conn, base, attrs) do
    body =
      Map.merge(
        %{
          kind: "pt_session",
          format: "one_to_one",
          starts_at: DateTime.utc_now() |> DateTime.add(2 * 3600) |> DateTime.truncate(:second),
          duration_minutes: 60
        },
        attrs
      )

    coach_conn
    |> send_json(:post, "#{base}/staff/appointment-slots", body)
    |> json_response(201)
    |> Map.fetch!("slot")
  end

  defp sessions(user), do: Finance.get_effective_entitlement(user.id).allowances[:pt_sessions]

  @two_sessions %{
    "personal_training.sessions" => %{"limit" => 2, "period" => "subscription_period"}
  }

  test "clients book matching PT slots, cancel and attend", %{
    conn: conn,
    coach: coach,
    coach_conn: coach_conn,
    base: base
  } do
    one = slot(coach_conn, base, %{})
    semi = slot(coach_conn, base, %{format: "semi_private", capacity: 2})
    {user, client_conn} = client(conn, @two_sessions)

    offered =
      client_conn
      |> recycle()
      |> get("#{base}/me/appointments/slots")
      |> json_response(200)
      |> Map.fetch!("slots")

    assert Enum.map(offered, & &1["id"]) == [one["id"]]

    assert %{"code" => "appointment_format_not_included"} =
             client_conn
             |> send_json(:post, "#{base}/me/appointments", %{slot_id: semi["id"]})
             |> json_response(403)

    booking =
      client_conn
      |> send_json(:post, "#{base}/me/appointments", %{slot_id: one["id"]})
      |> json_response(201)
      |> Map.fetch!("appointment")

    assert Enum.any?(Notifications.list_for_user(coach.id), &(&1.type == "appointment_booked"))

    {_other, other_conn} = client(conn, @two_sessions)

    assert %{"code" => "appointment_slot_full"} =
             other_conn
             |> send_json(:post, "#{base}/me/appointments", %{slot_id: one["id"]})
             |> json_response(409)

    assert %{"appointment" => %{"status" => "cancelled", "late_cancellation" => false}} =
             client_conn
             |> send_json(:post, "#{base}/me/appointments/#{booking["id"]}/cancel", %{})
             |> json_response(200)

    assert %{committed: 0} = sessions(user)

    again =
      client_conn
      |> send_json(:post, "#{base}/me/appointments", %{slot_id: one["id"]})
      |> json_response(201)
      |> Map.fetch!("appointment")

    assert %{"appointment" => %{"status" => "attended"}} =
             coach_conn
             |> send_json(:post, "#{base}/staff/appointments/#{again["id"]}/attendance", %{
               status: "attended"
             })
             |> json_response(200)

    assert %{committed: 1} = sessions(user)

    assert [%{"status" => "attended"}, %{"status" => "cancelled"}] =
             client_conn
             |> recycle()
             |> get("#{base}/me/appointments")
             |> json_response(200)
             |> Map.fetch!("appointments")
             |> Enum.sort_by(& &1["status"])
  end

  test "late cancellations use the session; staff cancellations and cancelled slots give it back",
       %{
         conn: conn,
         coach_conn: coach_conn,
         base: base
       } do
    {user, client_conn} =
      client(conn, Map.put(@two_sessions, "booking.cancellation_cutoff_hours", 24))

    first = slot(coach_conn, base, %{})

    second =
      slot(coach_conn, base, %{
        starts_at: DateTime.utc_now() |> DateTime.add(3 * 3600) |> DateTime.truncate(:second)
      })

    late =
      client_conn
      |> send_json(:post, "#{base}/me/appointments", %{slot_id: first["id"]})
      |> json_response(201)
      |> Map.fetch!("appointment")

    assert %{"appointment" => %{"late_cancellation" => true}} =
             client_conn
             |> send_json(:post, "#{base}/me/appointments/#{late["id"]}/cancel", %{})
             |> json_response(200)

    assert %{committed: 1} = sessions(user)

    by_staff =
      coach_conn
      |> send_json(:post, "#{base}/staff/appointment-slots/#{second["id"]}/bookings", %{
        user_id: user.id
      })
      |> json_response(201)
      |> Map.fetch!("appointment")

    assert by_staff["user_id"] == user.id
    assert %{committed: 2} = sessions(user)

    coach_conn
    |> send_json(:post, "#{base}/staff/appointment-slots/#{second["id"]}/cancel", %{})
    |> json_response(200)

    assert %{committed: 1} = sessions(user)
    assert Enum.any?(Notifications.list_for_user(user.id), &(&1.type == "appointment_cancelled"))

    assert %{"code" => "appointment_slot_cancelled"} =
             client_conn
             |> send_json(:post, "#{base}/me/appointments", %{slot_id: second["id"]})
             |> json_response(409)
  end

  test "assessments use their own allowance and clients without PT cannot book", %{
    conn: conn,
    coach_conn: coach_conn,
    base: base
  } do
    first = slot(coach_conn, base, %{kind: "assessment", duration_minutes: 45})

    second =
      slot(coach_conn, base, %{
        kind: "assessment",
        duration_minutes: 45,
        starts_at: DateTime.utc_now() |> DateTime.add(5 * 3600) |> DateTime.truncate(:second)
      })

    {_user, client_conn} = client(conn, %{"personal_training.assessments" => 1})

    client_conn
    |> send_json(:post, "#{base}/me/appointments", %{slot_id: first["id"]})
    |> json_response(201)

    assert %{"code" => "finance_allowance_exhausted"} =
             client_conn
             |> send_json(:post, "#{base}/me/appointments", %{slot_id: second["id"]})
             |> json_response(409)

    {_plain, plain_conn} =
      client(conn, %{
        "personal_training.assessments" => 0,
        "personal_training.included" => true,
        "personal_training.sessions" => %{"limit" => 1, "period" => "subscription_period"}
      })

    assert plain_conn
           |> send_json(:post, "#{base}/me/appointments", %{slot_id: second["id"]})
           |> json_response(403)

    assert %{"code" => "appointment_coach_not_staff"} =
             coach_conn
             |> send_json(:post, "#{base}/staff/appointment-slots", %{
               coach_id: Ecto.UUID.generate(),
               kind: "pt_session",
               format: "one_to_one",
               starts_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
               duration_minutes: 60
             })
             |> json_response(422)
  end
end
