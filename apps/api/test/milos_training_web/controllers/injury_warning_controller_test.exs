defmodule MilosTrainingWeb.InjuryWarningControllerTest do
  @moduledoc "ADR-114 injury warning endpoints (requests run RLS-enforced)."
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{AdminReportInjury, ReportInjury}
  alias MilosTraining.{Organizations, Scheduling, TestFixtures, Workouts}

  setup do
    {org, owner, staff} = organization_fixture()
    athlete = TestFixtures.user_fixture(%{role: :athlete})
    add_membership(org, athlete, :athlete)
    {:ok, athlete_context} = Organizations.resolve_tenant_context(athlete, org.slug)

    {:ok, workout} =
      Workouts.create_workout(staff, owner, %{
        title: "Legs #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Back Squat",
                order: 1,
                sets: 5,
                prescription_value: 5,
                prescription_unit: "reps"
              },
              %{
                name: "Box Jump",
                order: 2,
                sets: 3,
                prescription_value: 10,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      })

    {:ok, _org_injury} =
      AdminReportInjury.call(staff, owner.id, athlete.id, %{
        "body_area" => "knee",
        "severity" => "moderate",
        "training_limitations" => "No deep squats",
        "visibility" => "user_and_admin"
      })

    {:ok, _personal} =
      ReportInjury.call(athlete_context, athlete.id, %{
        "body_area" => "ankle",
        "severity" => "mild"
      })

    %{
      org: org,
      owner: owner,
      staff: staff,
      athlete: athlete,
      athlete_context: athlete_context,
      workout: workout
    }
  end

  defp staff_body(ctx, extra \\ %{}) do
    Map.merge(
      %{workout_id: ctx.workout.id, user_ids: [ctx.athlete.id], surface: "assign_dialog"},
      extra
    )
  end

  test "staff evaluate athletes and only see organization-provenance injuries",
       %{conn: conn} = ctx do
    response =
      conn
      |> put_bearer_token(ctx.owner)
      |> post("/api/org/#{ctx.org.slug}/admin/wellbeing/injury-warnings", staff_body(ctx))
      |> json_response(200)

    assert response["workout_id"] == ctx.workout.id
    assert response["level"] == "avoid"

    assert [%{"user_id" => user_id, "level" => "avoid", "warnings" => [warning]}] =
             response["athletes"]

    assert user_id == ctx.athlete.id
    assert warning["body_area"] == "knee"
    assert warning["provenance"] == "organization"
    assert warning["training_limitations"] == "No deep squats"

    assert Enum.sort(Enum.map(warning["exercises"], & &1["exercise_ref"])) == [
             "back-squat",
             "box-jump"
           ]

    ack =
      conn
      |> recycle()
      |> put_bearer_token(ctx.owner)
      |> post(
        "/api/org/#{ctx.org.slug}/admin/wellbeing/injury-warnings/acknowledge",
        staff_body(ctx)
      )
      |> json_response(200)

    assert ack == %{"acknowledged_count" => 1}
    assert [_shown] = analytics_events(ctx.org.id, "injury_warning_shown")
    assert [_ack] = analytics_events(ctx.org.id, "injury_warning_acknowledged")
  end

  test "staff see warnings for members booked into a class slot", %{conn: conn} = ctx do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: ctx.staff})

    slot =
      TestFixtures.slot_fixture(ctx.workout, %{
        tenant_context: ctx.staff,
        class_type_id: class_type.id
      })

    {:ok, _booking} = Scheduling.submit_booking(ctx.athlete_context, ctx.athlete.id, slot.id, 60)

    response =
      conn
      |> put_bearer_token(ctx.owner)
      |> get("/api/org/#{ctx.org.slug}/admin/schedule/slots/#{slot.id}/injury-warnings")
      |> json_response(200)

    assert response["slot_id"] == slot.id
    assert [%{"warnings" => [%{"body_area" => "knee"}]}] = response["athletes"]
  end

  test "the athlete sees own warnings including personal injuries and can acknowledge",
       %{conn: conn} = ctx do
    response =
      conn
      |> put_bearer_token(ctx.athlete)
      |> get(
        "/api/org/#{ctx.org.slug}/me/workouts/#{ctx.workout.id}/injury-warnings?surface=assignment_detail"
      )
      |> json_response(200)

    assert response["level"] == "avoid"

    assert response["warnings"] |> Enum.map(& &1["provenance"]) |> Enum.sort() == [
             "organization",
             "personal"
           ]

    ack =
      conn
      |> recycle()
      |> put_bearer_token(ctx.athlete)
      |> post(
        "/api/org/#{ctx.org.slug}/me/workouts/#{ctx.workout.id}/injury-warnings/acknowledge",
        %{
          surface: "pre_start"
        }
      )
      |> json_response(200)

    assert ack == %{"level" => "avoid", "warning_count" => 2}

    [event] = analytics_events(ctx.org.id, "injury_warning_acknowledged")
    assert event.metadata["audience"] == "self"
    assert event.metadata["injury_warning_count"] == 1
  end

  test "athletes cannot use the staff endpoints", %{conn: conn} = ctx do
    conn
    |> put_bearer_token(ctx.athlete)
    |> post("/api/org/#{ctx.org.slug}/admin/wellbeing/injury-warnings", staff_body(ctx))
    |> json_response(403)
  end

  test "another tenant's staff cannot read this tenant's workout or slots", %{conn: conn} = ctx do
    {other_org, other_owner, _other_staff} = organization_fixture()

    conn
    |> put_bearer_token(other_owner)
    |> post("/api/org/#{other_org.slug}/admin/wellbeing/injury-warnings", staff_body(ctx))
    |> json_response(404)
  end

  test "rejects unknown surfaces and malformed ids", %{conn: conn} = ctx do
    conn
    |> put_bearer_token(ctx.owner)
    |> post(
      "/api/org/#{ctx.org.slug}/admin/wellbeing/injury-warnings",
      staff_body(ctx, %{surface: "somewhere"})
    )
    |> json_response(422)

    conn
    |> recycle()
    |> put_bearer_token(ctx.athlete)
    |> get("/api/org/#{ctx.org.slug}/me/workouts/not-a-uuid/injury-warnings")
    |> json_response(422)
  end
end
