defmodule PaleeWeb.ExecutionInteractionsControllerTest do
  @moduledoc "ADR-123: execution interaction ingestion and assignment-open command endpoints."
  use PaleeWeb.ConnCase, async: false

  import Palee.AnalyticsHelpers

  alias Palee.Application.{AssignWorkout, StartWorkoutExecution}
  alias Palee.TestFixtures

  defp started_execution do
    {organization, owner, context} = organization_fixture()
    {member, member_context} = member_context(organization)
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: context})

    {:ok, execution} =
      StartWorkoutExecution.call(member_context, member, %{
        "master_workout_id" => workout.id,
        "source" => "self_selected"
      })

    %{organization: organization, member: member, execution: execution}
  end

  defp interaction(
         kind \\ "pause",
         metadata \\ %{"segment_index" => 2, "surface" => "pause_sheet"}
       ) do
    %{
      "client_event_id" => Ecto.UUID.generate(),
      "kind" => kind,
      "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "metadata" => metadata
    }
  end

  defp post_interactions(conn, user, execution_id, events) do
    conn
    |> put_bearer_token(user)
    |> post("/api/executions/#{execution_id}/interactions", Jason.encode!(%{events: events}))
  end

  describe "POST /api/executions/:id/interactions" do
    test "records allowlisted interactions in the execution's tenant and dedupes retries",
         %{conn: conn} do
      %{organization: organization, member: member, execution: execution} = started_execution()

      batch = [
        interaction(),
        interaction("round_incremented", %{"round_count" => 3, "format" => "amrap"}),
        interaction("finish_wizard_saved", %{"step" => 1, "scored_section_count" => 1})
      ]

      assert %{"accepted" => 3, "duplicates" => 0} =
               conn |> post_interactions(member, execution.id, batch) |> json_response(202)

      assert %{"accepted" => 0, "duplicates" => 3} =
               build_conn()
               |> post_interactions(member, execution.id, batch)
               |> json_response(202)

      events = analytics_events(organization.id, "execution_interaction")
      assert length(events) == 3
      pause = Enum.find(events, &(&1.metadata["kind"] == "pause"))

      assert pause.user_id == member.id
      assert pause.context_type == "workout_execution"
      assert pause.context_id == execution.id
      assert pause.dedupe_key == "#{member.id}:#{hd(batch)["client_event_id"]}"

      assert pause.metadata == %{
               "kind" => "pause",
               "client_event_id" => hd(batch)["client_event_id"],
               "segment_index" => 2,
               "surface" => "pause_sheet"
             }
    end

    test "rejects the whole batch when any kind or field is outside the allowlist",
         %{conn: conn} do
      %{organization: organization, member: member, execution: execution} = started_execution()

      body =
        conn
        |> post_interactions(member, execution.id, [interaction(), interaction("dance", %{})])
        |> json_response(422)

      assert body["code"] == "invalid_execution_interactions"
      assert [%{"index" => 1, "reason" => "unknown_kind"}] = body["errors"]

      body =
        build_conn()
        |> post_interactions(member, execution.id, [
          interaction("pause", %{"note" => "free text"})
        ])
        |> json_response(422)

      assert [%{"reason" => "metadata_field_not_allowed"}] = body["errors"]
      assert analytics_events(organization.id, "execution_interaction") == []
    end

    test "only the execution owner can report interactions", %{conn: conn} do
      %{organization: organization, execution: execution} = started_execution()
      %{member: intruder, organization: other_org} = started_execution()

      conn
      |> post_interactions(intruder, execution.id, [interaction()])
      |> json_response(404)

      build_conn()
      |> post_interactions(intruder, "not-a-uuid", [interaction()])
      |> json_response(404)

      assert analytics_events(organization.id, "execution_interaction") == []
      assert analytics_events(other_org.id, "execution_interaction") == []
    end

    test "is rate limited per user in its own bucket", %{conn: conn} do
      %{member: member} = started_execution()
      missing = Ecto.UUID.generate()

      for _ <- 1..60 do
        conn
        |> recycle()
        |> post_interactions(member, missing, [interaction()])
        |> json_response(404)
      end

      assert %{"code" => "rate_limited"} =
               conn
               |> recycle()
               |> post_interactions(member, missing, [interaction()])
               |> json_response(429)
    end
  end

  test "the OpenAPI metadata schema lists exactly the allowlisted typed fields" do
    schema = PaleeWeb.ExecutionController.interaction_metadata_schema()

    assert schema.properties |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort() ==
             Palee.Analytics.execution_interaction_fields()
  end

  describe "POST /api/org/:slug/my-workouts/assignments/:id/open" do
    test "records one open per athlete per day and hides foreign assignments", %{conn: conn} do
      {organization, owner, context} = organization_fixture()
      {athlete, _athlete_context} = member_context(organization, :athlete)
      {other_athlete, _} = member_context(organization, :athlete)
      TestFixtures.programming_grant_fixture(context, athlete)
      workout = TestFixtures.workout_fixture(owner, %{tenant_context: context})

      {:ok, assignment} =
        AssignWorkout.call(context, %{
          master_workout_id: workout.id,
          athlete_ids: [athlete.id],
          scheduled_for: Date.utc_today()
        })

      path = "/api/org/#{organization.slug}/my-workouts/assignments/#{assignment.id}/open"

      assert conn |> put_bearer_token(athlete) |> post(path) |> response(204) == ""
      assert build_conn() |> put_bearer_token(athlete) |> post(path) |> response(204) == ""
      build_conn() |> put_bearer_token(other_athlete) |> post(path) |> json_response(404)

      event = analytics_event!(organization.id, "workout_assignment_opened")
      assert event.user_id == athlete.id
      assert event.context_id == assignment.id
    end
  end
end
