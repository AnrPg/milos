defmodule MilosTrainingWeb.AdminUserDirectoryControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.{
    Finance,
    Gamification,
    Messaging,
    Organizations,
    Repo,
    Workouts,
    Workouts.MasterWorkout,
    Workouts.WorkoutFolder
  }

  alias MilosTraining.Gamification.SeasonalChallenge
  alias MilosTraining.Messaging.{Message, Participant}

  test "admin lists all roles and filters by role and nickname", %{conn: conn} do
    admin = admin_fixture(%{nickname: "directory_admin"})
    member = user_fixture(%{role: :member, nickname: "directory_member"})
    _athlete = user_fixture(%{role: :athlete, nickname: "directory_athlete"})

    all =
      conn
      |> put_bearer_token(admin)
      |> get("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users")
      |> json_response(200)

    assert all["meta"]["total"] >= 3
    assert Enum.any?(all["users"], &(&1["id"] == admin.id and &1["role"] == "admin"))

    filtered =
      build_conn()
      |> put_bearer_token(admin)
      |> get(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users?role=member&q=directory_mem"
      )
      |> json_response(200)

    assert [%{"id" => id, "role" => "member"}] = filtered["users"]
    assert id == member.id
  end

  test "tenant admin cannot list, open, finance, or mutate users from another org", %{
    conn: conn
  } do
    admin = admin_fixture(%{nickname: "tenant_directory_admin"})
    target = user_fixture(%{role: :member, nickname: "tenant_directory_foreign"})

    {_org_a, context_a} = tenant_fixture(admin, "Admin Directory A")
    {org_b, context_b} = tenant_fixture(target, "Admin Directory B", :member)

    {:ok, package} =
      Finance.create_package(context_b, %{
        code: "tenant_directory_foreign",
        name: "Tenant directory foreign",
        family: "limited-visits",
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 1,
          "channels" => ["in_person"],
          "capabilities" => ["book_classes"],
          "allowances" => %{
            "class_visits" => %{"limit" => 4, "period" => "calendar_month"}
          }
        }
      })

    {:ok, membership} =
      Finance.upsert_membership(context_b, target.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(context_b, membership.id, package.id, %{starts_on: Date.utc_today()})

    listing =
      conn
      |> put_bearer_token(admin)
      |> get("/api/org/#{context_a.organization.slug}/admin/users?q=tenant_directory_foreign")
      |> json_response(200)

    assert listing["users"] == []

    for path <- [
          "/api/org/#{context_a.organization.slug}/admin/users/#{target.id}",
          "/api/org/#{context_a.organization.slug}/admin/users/#{target.id}/finance"
        ] do
      response =
        build_conn()
        |> put_bearer_token(admin)
        |> get(path)
        |> json_response(404)

      assert response["code"] == "not_found"
    end

    allowance_response =
      build_conn()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{context_a.organization.slug}/admin/users/#{target.id}/allowance-extensions",
        %{
          allowance: "class_visits",
          quantity: 1,
          period: "calendar_month",
          reason: "Should not cross tenants"
        }
      )
      |> json_response(404)

    assert allowance_response["code"] == "not_found"

    assert Finance.get_effective_entitlement(context_b, target.id).allowances.class_visits.extensions ==
             0

    assert org_b.id == context_b.organization_id
  end

  test "admin opens a role-aware common profile shell", %{conn: conn} do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete, nickname: "profile_athlete"})

    response =
      conn
      |> put_bearer_token(admin)
      |> get(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{athlete.id}"
      )
      |> json_response(200)

    assert response["user"]["identity"]["nickname"] == "profile_athlete"
    assert response["user"]["account_status"] == "active"
    assert "finance" in response["user"]["available_sections"]
    assert "coaching_context" in response["user"]["available_sections"]
  end

  test "unknown users return not found", %{conn: conn} do
    admin = admin_fixture()

    response =
      conn
      |> put_bearer_token(admin)
      |> get(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{Ecto.UUID.generate()}"
      )
      |> json_response(404)

    assert response["error"] == "Not found"
  end

  test "focused dossier endpoints expose stable empty states for a member", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "dossier_member"})

    finance = get_as_admin(conn, admin, member.id, "finance")
    assert finance["user_id"] == member.id
    assert finance["summary"]["credit_balance"] == 0

    assert finance["operational_links"]["workspace"] ==
             "/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/finance"

    training = get_as_admin(build_conn(), admin, member.id, "training-history")
    assert training["executions"] == []
    assert training["scores"] == []
    assert training["class_participation"] == []

    prs = get_as_admin(build_conn(), admin, member.id, "prs")
    assert prs == %{"prs" => [], "user_id" => member.id}

    incidents = get_as_admin(build_conn(), admin, member.id, "incidents")

    assert incidents == %{
             "incidents" => [],
             "summary" => %{"active" => 0, "total" => 0},
             "user_id" => member.id
           }

    messages = get_as_admin(build_conn(), admin, member.id, "messages")
    assert messages["threads"] == []
    assert messages["summary"] == %{"thread_count" => 0, "unread_thread_count" => 0}
  end

  test "focused dossier endpoints compose PR, injury, and message records", %{conn: conn} do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete, nickname: "dossier_athlete"})

    {:ok, _pr} =
      MilosTraining.Application.CreatePR.call(athlete.id, %{
        "name" => "Back squat",
        "current_score" => 120,
        "unit" => "kg",
        "beaten_on" => Date.to_iso8601(Date.utc_today())
      })

    {:ok, _injury} =
      MilosTraining.Application.AdminReportInjury.call(admin.id, athlete.id, %{
        "body_area" => "shoulder",
        "severity" => "moderate",
        "training_limitations" => "No overhead work"
      })

    {:ok, thread} =
      MilosTraining.Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: athlete.id
      })

    {:ok, _message} =
      MilosTraining.Messaging.send_message(%{
        thread_id: thread.id,
        sender_id: admin.id,
        body: "Keep the next session easy"
      })

    assert [%{"name" => "Back squat", "unit" => "kg"}] =
             get_as_admin(conn, admin, athlete.id, "prs")["prs"]

    assert [%{"body_area" => "shoulder", "status" => "active"}] =
             get_as_admin(build_conn(), admin, athlete.id, "incidents")["incidents"]

    [message_thread] = get_as_admin(build_conn(), admin, athlete.id, "messages")["threads"]
    assert message_thread["id"] == thread.id
    assert message_thread["latest_message"]["body"] == "Keep the next session easy"
  end

  test "athlete coaching context is available while other roles receive a role-safe empty state",
       %{conn: conn} do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    member = user_fixture(%{role: :member})

    athlete_payload = get_as_admin(conn, admin, athlete.id, "coaching-context")
    assert athlete_payload["available"] == true
    assert is_map(athlete_payload["drill_down"])

    member_payload = get_as_admin(build_conn(), admin, member.id, "coaching-context")
    assert member_payload == %{"available" => false, "drill_down" => nil, "user_id" => member.id}
  end

  test "non-admin users cannot access the directory", %{conn: conn} do
    member = user_fixture(%{role: :member})

    conn =
      conn
      |> put_bearer_token(member)
      |> get("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users")

    assert json_response(conn, 403)["error"] == "Forbidden"
  end

  test "admin extends one user's allowance from the unified profile contract", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})

    {:ok, package} =
      MilosTraining.Finance.create_package(%{
        code: "profile_extension_package",
        name: "Profile extension package",
        family: "limited-visits",
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 1,
          "channels" => ["in_person"],
          "capabilities" => ["book_classes"],
          "allowances" => %{
            "class_visits" => %{"limit" => 4, "period" => "calendar_month"}
          }
        }
      })

    {:ok, membership} =
      MilosTraining.Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      MilosTraining.Finance.assign_package(membership.id, package.id, %{
        starts_on: Date.utc_today()
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{member.id}/allowance-extensions",
        %{
          allowance: "class_visits",
          quantity: 2,
          period: "calendar_month",
          reason: "Competition preparation"
        }
      )
      |> json_response(201)

    assert response["entry"]["allowance_key"] == "class_visits"
    assert response["entry"]["quantity_delta"] == -2

    entitlement = response["entitlement"]
    assert entitlement["allowances"]["class_visits"]["extensions"] == 2
    assert entitlement["allowances"]["class_visits"]["remaining"] == 6

    revoked =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{member.id}/allowance-extensions/#{response["entry"]["id"]}/revoke",
        %{reason: "Competition cancelled"}
      )
      |> json_response(201)

    assert revoked["entry"]["parent_entry_id"] == response["entry"]["id"]
    assert revoked["entry"]["quantity_delta"] == 2
    assert revoked["entitlement"]["allowances"]["class_visits"]["extensions"] == 0
  end

  test "admin can delete another user's account", %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture(%{role: :athlete, nickname: "delete_target"})

    response =
      conn
      |> put_bearer_token(admin)
      |> delete(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{user.id}"
      )

    assert response.status == 204
    assert MilosTraining.Identity.find_by_id(user.id) == nil
  end

  test "admin can delete a user with messaging history", %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture(%{role: :athlete, nickname: "delete_message_target"})

    {:ok, thread} =
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: user.id
      })

    {:ok, message} =
      Messaging.send_message(%{
        thread_id: thread.id,
        sender_id: user.id,
        body: "Please delete my account"
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> delete(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{user.id}"
      )

    assert response.status == 204
    assert MilosTraining.Identity.find_by_id(user.id) == nil
    assert Repo.get(Message, message.id) == nil
    assert Repo.get_by(Participant, user_id: user.id) == nil
  end

  test "admin authored content is detached instead of blocking account deletion", %{conn: conn} do
    owner = admin_fixture(%{nickname: "deletable_content_admin"})
    admin = admin_fixture(%{nickname: "remaining_content_admin"})

    {:ok, folder} = Workouts.create_folder(owner.id, %{name: "Owner folder"})
    {:ok, draft} = Workouts.create_draft(owner)

    {:ok, challenge} =
      Gamification.create_seasonal_challenge(owner.id, %{
        "title" => "Owner challenge",
        "criteria_type" => "workout_count",
        "criteria_value" => %{"count" => 3},
        "badge_key" => "owner_delete_badge",
        "badge_label" => "Owner Delete",
        "starts_at" => Date.utc_today(),
        "ends_at" => Date.add(Date.utc_today(), 7)
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> delete(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{owner.id}"
      )

    assert response.status == 204
    assert MilosTraining.Identity.find_by_id(owner.id) == nil
    assert Repo.get(MasterWorkout, draft.id).created_by_id == nil
    assert Repo.get(WorkoutFolder, folder.id).created_by_id == nil
    assert Repo.get(SeasonalChallenge, challenge.id).created_by_id == nil
  end

  test "admin cannot delete their own account", %{conn: conn} do
    admin = admin_fixture()

    response =
      conn
      |> put_bearer_token(admin)
      |> delete(
        "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{admin.id}"
      )
      |> json_response(422)

    assert response["code"] == "cannot_delete_self"
  end

  defp get_as_admin(conn, admin, user_id, section) do
    conn
    |> put_bearer_token(admin)
    |> get(
      "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/users/#{user_id}/#{section}"
    )
    |> json_response(200)
  end

  defp tenant_fixture(user, name, role \\ :owner) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "#{name} #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
  end
end
