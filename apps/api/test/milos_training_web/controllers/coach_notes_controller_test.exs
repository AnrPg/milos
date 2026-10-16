defmodule MilosTrainingWeb.CoachNotesControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Coaching, Notifications, Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    coach = person.(:coach)
    other_coach = person.(:coach)
    athlete = person.(:athlete)

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: organization.id}, %{
        coach_user_id: coach.id,
        client_user_id: athlete.id,
        origin: "assigned"
      })

    owner = person.(:owner)
    admin = person.(:admin)

    %{
      conn: conn,
      coach: coach,
      athlete: athlete,
      admin: admin,
      as: fn user -> put_bearer_token(conn, user) end,
      other_coach: other_coach,
      owner: owner,
      base: "/api/org/#{Organizations.legacy_organization_slug()}/staff"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "owners read notes quietly, admins only when allowed and the coach is told", ctx do
    %{as: as, coach: coach, athlete: athlete, base: base} = ctx
    notes_path = "#{base}/clients/#{athlete.id}/coach-notes"

    assert %{"note" => %{"id" => note_id}} =
             as.(coach)
             |> send_json(:post, notes_path, %{body: "Knee pain on deep squats"})
             |> json_response(201)

    # Another coach neither writes about nor reads someone else's client.
    assert as.(ctx.other_coach)
           |> send_json(:post, notes_path, %{body: "x"})
           |> json_response(403)

    assert as.(ctx.other_coach) |> get(notes_path) |> json_response(403)

    assert [%{"id" => ^note_id}] =
             as.(ctx.owner) |> get(notes_path) |> json_response(200) |> Map.fetch!("notes")

    refute Enum.any?(Notifications.list_for_user(coach.id), &(&1.type == "coach_note_viewed"))

    assert [%{"id" => ^note_id}] =
             as.(ctx.admin) |> get(notes_path) |> json_response(200) |> Map.fetch!("notes")

    assert Enum.any?(Notifications.list_for_user(coach.id), &(&1.type == "coach_note_viewed"))

    assert %{"visible_to_admins" => false} =
             as.(coach)
             |> send_json(:put, "#{base}/me/notes-visibility", %{visible_to_admins: false})
             |> json_response(200)

    assert [] = as.(ctx.admin) |> get(notes_path) |> json_response(200) |> Map.fetch!("notes")
    assert [_] = as.(ctx.owner) |> get(notes_path) |> json_response(200) |> Map.fetch!("notes")

    reads =
      as.(coach) |> get("#{base}/coach-notes/reads") |> json_response(200) |> Map.fetch!("reads")

    assert length(reads) == 3
    assert Enum.all?(reads, &(&1["note_id"] == note_id))

    assert as.(ctx.admin)
           |> send_json(:patch, "#{base}/coach-notes/#{note_id}", %{body: "edit"})
           |> json_response(403)

    assert %{"note" => %{"body" => "Better"}} =
             as.(coach)
             |> send_json(:patch, "#{base}/coach-notes/#{note_id}", %{body: "Better"})
             |> json_response(200)
  end

  test "a note can be about one thing of the client's, never someone else's", ctx do
    %{as: as, coach: coach, athlete: athlete, base: base} = ctx
    stranger = user_fixture()
    notes_path = "#{base}/clients/#{athlete.id}/coach-notes"

    {:ok, injury} =
      MilosTraining.Wellbeing.report_injury(athlete.id, athlete.id, "self", %{
        body_area: "knee",
        severity: "mild"
      })

    {:ok, foreign} =
      MilosTraining.Wellbeing.report_injury(stranger.id, stranger.id, "self", %{
        body_area: "knee",
        severity: "mild"
      })

    assert %{"note" => %{"subject_kind" => "injury", "subject_id" => subject_id}} =
             as.(coach)
             |> send_json(:post, notes_path, %{
               body: "Keep squats above parallel",
               subject_kind: "injury",
               subject_id: injury.id
             })
             |> json_response(201)

    assert subject_id == injury.id

    assert as.(coach)
           |> send_json(:post, notes_path, %{
             body: "Not theirs",
             subject_kind: "injury",
             subject_id: foreign.id
           })
           |> json_response(422)

    assert as.(coach)
           |> send_json(:post, notes_path, %{body: "Half a subject", subject_kind: "pr"})
           |> json_response(422)
  end
end
