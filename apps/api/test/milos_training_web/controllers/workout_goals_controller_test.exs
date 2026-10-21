defmodule MilosTrainingWeb.WorkoutGoalsControllerTest do
  @moduledoc "ADR-163 WOD goal, «τι ένιωσες» and taxonomy endpoints (requests run RLS-enforced)."
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.LogTrainingEntry
  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Repo, TestFixtures}

  setup do
    {org, owner, staff} = organization_fixture()
    {member, member_context} = member_context(org)
    {athlete, _athlete_context} = member_context(org, :athlete)

    workout =
      TestFixtures.workout_fixture(owner, %{
        tenant_context: staff,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [
              %{name: "Thrusters", order: 1, sets: 3, prescription_value: 15},
              %{name: "Pull-ups", order: 2, sets: 3, prescription_value: 15}
            ]
          }
        ]
      })

    %{
      org: org,
      owner: owner,
      member: member,
      member_context: member_context,
      athlete: athlete,
      workout: workout
    }
  end

  defp admin_path(ctx), do: "/api/org/#{ctx.org.slug}/admin/workouts/#{ctx.workout.id}/goals"
  defp member_path(ctx), do: "/api/org/#{ctx.org.slug}/workouts/#{ctx.workout.id}/goals"

  defp feedback_path(ctx, kind, id),
    do: "/api/org/#{ctx.org.slug}/me/goal-feedback/#{kind}/#{id}"

  @goals %{
    muscles: [
      %{id: "quadriceps", role: "primary"},
      %{id: "latissimus-dorsi", role: "primary"},
      %{id: "deltoid", role: "secondary"}
    ],
    qualities: ["stamina", "power"],
    stimulus: "Unbroken sets"
  }

  defp save_goals(conn, ctx, extra \\ %{}) do
    conn
    |> recycle()
    |> put_bearer_token(ctx.owner)
    |> put(admin_path(ctx), Map.merge(@goals, extra))
  end

  describe "staff goals" do
    test "read the suggestion, save goals and reset to it", %{conn: conn} = ctx do
      response =
        conn
        |> put_bearer_token(ctx.owner)
        |> get(admin_path(ctx))
        |> json_response(200)

      assert %{"goals" => goals, "suggestion" => suggestion} = response
      assert goals["saved"] == false
      assert goals["source"] == "suggested"
      assert goals["muscles"] == suggestion["muscles"]
      assert suggestion["matched_exercises"] == 2
      assert suggestion["unmatched_exercises"] == 0
      assert %{"id" => "latissimus-dorsi", "role" => "primary"} in suggestion["muscles"]

      saved = conn |> save_goals(ctx, %{visible_to_members: true}) |> json_response(200)

      assert saved["goals"]["saved"] == true
      assert saved["goals"]["source"] == "edited"
      assert saved["goals"]["visible_to_members"] == true
      assert saved["goals"]["stimulus"] == "Unbroken sets"
      assert saved["goals"]["updated_by_id"] == ctx.owner.id
      assert saved["suggestion"] == suggestion

      reset =
        conn
        |> recycle()
        |> put_bearer_token(ctx.owner)
        |> put(admin_path(ctx), %{
          muscles: suggestion["muscles"],
          qualities: suggestion["qualities"]
        })
        |> json_response(200)

      assert reset["goals"]["source"] == "suggested"
      assert reset["goals"]["visible_to_members"] == true
    end

    test "invalid goals are rejected with 422", %{conn: conn} = ctx do
      body =
        conn
        |> save_goals(ctx, %{muscles: [%{id: "spleen", role: "primary"}]})
        |> json_response(422)

      assert body["code"] == "invalid_goals"
      assert body["errors"]["muscles"]
    end

    test "members and other gyms cannot use the staff routes", %{conn: conn} = ctx do
      conn
      |> put_bearer_token(ctx.member)
      |> get(admin_path(ctx))
      |> json_response(403)

      conn
      |> recycle()
      |> put_bearer_token(ctx.member)
      |> put(admin_path(ctx), @goals)
      |> json_response(403)

      {other_org, other_owner, _staff} = organization_fixture()

      conn
      |> recycle()
      |> put_bearer_token(other_owner)
      |> get("/api/org/#{other_org.slug}/admin/workouts/#{ctx.workout.id}/goals")
      |> json_response(404)

      conn
      |> recycle()
      |> put_bearer_token(other_owner)
      |> put("/api/org/#{other_org.slug}/admin/workouts/#{ctx.workout.id}/goals", @goals)
      |> json_response(404)
    end
  end

  describe "member goals" do
    test "hidden goals are null; visible goals are shown to members and athletes",
         %{conn: conn} = ctx do
      assert %{"goals" => nil} =
               conn |> put_bearer_token(ctx.member) |> get(member_path(ctx)) |> json_response(200)

      conn |> save_goals(ctx) |> json_response(200)

      assert %{"goals" => nil} =
               conn
               |> recycle()
               |> put_bearer_token(ctx.member)
               |> get(member_path(ctx))
               |> json_response(200)

      conn |> save_goals(ctx, %{visible_to_members: true}) |> json_response(200)

      for user <- [ctx.member, ctx.athlete] do
        body =
          conn
          |> recycle()
          |> put_bearer_token(user)
          |> get(member_path(ctx))
          |> json_response(200)

        assert body["workout_id"] == ctx.workout.id
        assert body["goals"]["stimulus"] == "Unbroken sets"
        assert body["goals"]["qualities"] == ["stamina", "power"]
        refute Map.has_key?(body["goals"], "visible_to_members")
      end
    end

    test "another gym cannot read them", %{conn: conn} = ctx do
      conn |> save_goals(ctx, %{visible_to_members: true}) |> json_response(200)

      {other_org, _owner, _staff} = organization_fixture()
      {other_member, _context} = member_context(other_org)

      conn
      |> recycle()
      |> put_bearer_token(other_member)
      |> get("/api/org/#{other_org.slug}/workouts/#{ctx.workout.id}/goals")
      |> json_response(404)

      # Not a member of the workout's gym at all.
      conn
      |> recycle()
      |> put_bearer_token(other_member)
      |> get(member_path(ctx))
      |> json_response(404)
    end
  end

  describe "goal feedback" do
    setup ctx do
      execution =
        Repo.insert!(%WorkoutExecution{
          user_id: ctx.member.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.workout.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        })

      %{execution: execution}
    end

    test "the owner reads and saves feedback on an execution", %{conn: conn} = ctx do
      conn |> save_goals(ctx, %{visible_to_members: true}) |> json_response(200)
      path = feedback_path(ctx, "execution", ctx.execution.id)

      body = conn |> recycle() |> put_bearer_token(ctx.member) |> get(path) |> json_response(200)

      assert body["entry_kind"] == "execution"
      assert body["entry_id"] == ctx.execution.id
      assert body["voided"] == false
      assert body["feedback"] == nil
      assert body["goals"]["stimulus"] == "Unbroken sets"

      saved =
        conn
        |> recycle()
        |> put_bearer_token(ctx.member)
        |> put(path, %{felt_muscles: ["quadriceps", "deltoid"], felt_qualities: ["stamina"]})
        |> json_response(200)

      assert saved["feedback"]["felt_muscles"] == ["deltoid", "quadriceps"]
      assert saved["feedback"]["felt_qualities"] == ["stamina"]

      again = conn |> recycle() |> put_bearer_token(ctx.member) |> get(path) |> json_response(200)
      assert again["feedback"]["felt_muscles"] == ["deltoid", "quadriceps"]

      invalid =
        conn
        |> recycle()
        |> put_bearer_token(ctx.member)
        |> put(path, %{felt_muscles: ["heart"], felt_qualities: []})
        |> json_response(422)

      assert invalid["code"] == "invalid_goals"
    end

    test "feedback on a training-log entry", %{conn: conn} = ctx do
      {:ok, entry, :created} =
        LogTrainingEntry.call(ctx.member_context, ctx.member, %{
          "source_type" => "library_workout",
          "source_reference_id" => ctx.workout.id,
          "performed_at" =>
            DateTime.utc_now() |> DateTime.add(-3 * 86_400) |> DateTime.to_iso8601(),
          "idempotency_key" => "goals-" <> Ecto.UUID.generate()
        })

      body =
        conn
        |> put_bearer_token(ctx.member)
        |> put(feedback_path(ctx, "training_log", entry.id), %{
          felt_muscles: ["latissimus-dorsi"],
          felt_qualities: []
        })
        |> json_response(200)

      assert body["entry_kind"] == "training_log"
      assert body["goals"] == nil
      assert body["feedback"]["felt_muscles"] == ["latissimus-dorsi"]

      # «Ένιωσα: …» rides on the entry in the journal feed.
      feed =
        conn
        |> recycle()
        |> put_bearer_token(ctx.member)
        |> get("/api/me/journal")
        |> json_response(200)

      item = Enum.find(feed["items"], &(&1["id"] == entry.id))
      assert item["entry"]["felt"] == %{"muscles" => ["latissimus-dorsi"], "qualities" => []}
    end

    test "another member cannot read or write someone's feedback", %{conn: conn} = ctx do
      path = feedback_path(ctx, "execution", ctx.execution.id)

      conn
      |> put_bearer_token(ctx.member)
      |> put(path, %{felt_muscles: ["quadriceps"], felt_qualities: []})
      |> json_response(200)

      conn
      |> recycle()
      |> put_bearer_token(ctx.athlete)
      |> get(path)
      |> json_response(404)

      conn
      |> recycle()
      |> put_bearer_token(ctx.athlete)
      |> put(path, %{felt_muscles: ["deltoid"], felt_qualities: []})
      |> json_response(404)

      conn
      |> recycle()
      |> put_bearer_token(ctx.owner)
      |> get(path)
      |> json_response(404)

      assert %{"feedback" => %{"felt_muscles" => ["quadriceps"]}} =
               conn
               |> recycle()
               |> put_bearer_token(ctx.member)
               |> get(path)
               |> json_response(200)
    end

    test "unknown entry kinds are rejected", %{conn: conn} = ctx do
      conn
      |> put_bearer_token(ctx.member)
      |> get(feedback_path(ctx, "pr", ctx.execution.id))
      |> json_response(422)
    end
  end

  describe "taxonomy" do
    test "authenticated, cacheable, answers 304 to its ETag", %{conn: conn} = ctx do
      conn |> get("/api/anatomy/taxonomy") |> json_response(401)

      response = conn |> recycle() |> put_bearer_token(ctx.member) |> get("/api/anatomy/taxonomy")
      body = json_response(response, 200)

      assert is_integer(body["version"])
      assert "strength" in body["qualities"]
      assert body["roles"] == ["primary", "secondary", "stabilizer"]

      assert %{"kind" => "region", "parent_id" => nil} =
               Enum.find(body["nodes"], &(&1["id"] == "thighs"))

      assert %{"kind" => "head", "parent_id" => "deltoid", "ta2_ids" => ["2453"]} =
               Enum.find(body["nodes"], &(&1["id"] == "deltoid-anterior"))

      [etag] = get_resp_header(response, "etag")
      assert get_resp_header(response, "cache-control") == ["private, max-age=86400"]

      cached =
        conn
        |> recycle()
        |> put_bearer_token(ctx.member)
        |> put_req_header("if-none-match", etag)
        |> get("/api/anatomy/taxonomy")

      assert cached.status == 304
    end
  end
end
