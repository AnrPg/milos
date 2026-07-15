defmodule MilosTrainingWeb.AdminClassTypeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Repo
  alias MilosTraining.Scheduling.{ClassType, ScheduledClass}

  test "admin creates and renames a class type", %{conn: conn} do
    admin = admin_fixture(%{nickname: "class_type_admin"})
    admin_conn = put_bearer_token(conn, admin)

    created =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/api/admin/class-types", Jason.encode!(%{name: "Olympic Lifting"}))
      |> json_response(201)
      |> Map.fetch!("class_type")

    assert created["slug"] == "olympic-lifting"
    assert created["name"] == "Olympic Lifting"
    assert created["archived_at"] == nil

    updated =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/admin/class-types/#{created["id"]}",
        Jason.encode!(%{name: "Olympic Weightlifting"})
      )
      |> json_response(200)
      |> Map.fetch!("class_type")

    assert updated["slug"] == "olympic-lifting"
    assert updated["name"] == "Olympic Weightlifting"
  end

  test "class type configuration is admin-only", %{conn: conn} do
    member = user_fixture(%{nickname: "class_type_member"})

    assert conn
           |> put_bearer_token(member)
           |> get("/api/admin/class-types")
           |> response(403)
  end

  test "the final active class type cannot be archived", %{conn: conn} do
    admin = admin_fixture(%{nickname: "last_class_type_admin"})

    Repo.update_all(ClassType,
      set: [archived_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )

    only_type = class_type_fixture(%{name: "Only Active", slug: "only-active"})

    response =
      conn
      |> put_bearer_token(admin)
      |> delete("/api/admin/class-types/#{only_type.id}")

    assert %{"error" => "At least one active class type must remain"} =
             json_response(response, 409)

    assert Repo.get!(ClassType, only_type.id).archived_at == nil
  end

  test "archival maps future classes while preserving past class history", %{conn: conn} do
    admin = admin_fixture(%{nickname: "class_type_archive_admin"})
    workout = workout_fixture(admin)
    source = class_type_fixture(%{name: "Legacy Class", slug: "legacy-class"})
    replacement = class_type_fixture(%{name: "Current Class", slug: "current-class"})

    past_slot =
      Repo.insert!(%ScheduledClass{
        master_workout_id: workout.id,
        class_type_id: source.id,
        scheduled_at:
          DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -3_600, :second),
        capacity: 10,
        auto_approve: false,
        booking_timeout_minutes: 60
      })

    future_slot = slot_fixture(workout, %{class_type_id: source.id})
    admin_conn = put_bearer_token(conn, admin)

    missing_mapping =
      delete(admin_conn |> recycle(), "/api/admin/class-types/#{source.id}")

    assert %{
             "error" => "Future classes require a replacement class type",
             "future_class_count" => 1
           } =
             json_response(missing_mapping, 409)

    archived =
      delete(
        admin_conn |> recycle(),
        "/api/admin/class-types/#{source.id}?replacement_class_type_id=#{replacement.id}"
      )
      |> json_response(200)

    assert archived["class_type"]["archived_at"]
    assert Repo.get!(ScheduledClass, past_slot.id).class_type_id == source.id
    assert Repo.get!(ScheduledClass, future_slot.id).class_type_id == replacement.id
    assert Repo.get!(ClassType, source.id).archived_at
  end

  test "schedule creation requires an explicit class type and filters by multiple ids", %{
    conn: conn
  } do
    admin = admin_fixture(%{nickname: "class_type_schedule_admin"})
    member = user_fixture(%{nickname: "class_type_schedule_member"})
    workout = workout_fixture(admin)
    strength = class_type_fixture(%{name: "Strength Class", slug: "strength-class"})
    recovery = class_type_fixture(%{name: "Recovery Class", slug: "recovery-class"})
    admin_conn = put_bearer_token(conn, admin)

    missing_type =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/admin/schedule/slots",
        Jason.encode!(%{
          master_workout_id: workout.id,
          scheduled_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
          capacity: 10,
          auto_approve: false,
          booking_timeout_minutes: 60
        })
      )

    assert response(missing_type, 422)

    first = slot_fixture(workout, %{class_type_id: strength.id})

    second =
      slot_fixture(workout, %{
        class_type_id: recovery.id,
        scheduled_at:
          DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 7_200, :second)
      })

    response =
      get(
        put_bearer_token(conn, member),
        "/api/schedule?start_date=#{Date.utc_today()}&days=7&class_type_ids[]=#{strength.id}&class_type_ids[]=#{recovery.id}"
      )
      |> json_response(200)

    ids = Enum.map(response["slots"], & &1["id"])
    assert first.id in ids
    assert second.id in ids
    assert Enum.any?(response["class_types"], &(&1["id"] == strength.id))
  end
end
