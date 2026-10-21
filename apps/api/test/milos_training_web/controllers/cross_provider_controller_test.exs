defmodule MilosTrainingWeb.CrossProviderControllerTest do
  @moduledoc """
  ADR-162 over HTTP: Box ▾ providers and the remembered choice, the merged
  «Σήμερα» (resilient to one provider failing), account history, Πρόοδος
  and Vault across two providers, the Ροή filter, «Οι coach μου» and the
  journal export.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Organizations, Repo}

  setup %{conn: conn} do
    box = org!("Box Kypseli")
    coach_org = org!("Nikos PT")
    owner = user_fixture()
    member = user_fixture()
    add!(box, owner, [:owner, :coach])
    add!(coach_org, owner, [:owner, :coach])
    add!(box, member, [:member])
    add!(coach_org, member, [:member])

    %{conn: conn, box: box, coach_org: coach_org, owner: owner, member: member}
  end

  defp authed(ctx), do: ctx.conn |> recycle() |> put_bearer_token(ctx.member)

  test "providers list both, remembers the choice and refuses a stranger", ctx do
    body = authed(ctx) |> get("/api/me/providers") |> json_response(200)

    assert [%{"name" => "Box Kypseli", "selected" => true}, %{"name" => "Nikos PT"}] =
             body["providers"]

    assert body["former"] == []
    assert body["selected_organization_id"] == ctx.box.id

    body =
      authed(ctx)
      |> put("/api/me/providers/selected", %{organization_id: ctx.coach_org.id})
      |> json_response(200)

    assert body["selected_organization_id"] == ctx.coach_org.id

    assert authed(ctx)
           |> get("/api/me/providers")
           |> json_response(200)
           |> Map.get("selected_organization_id") == ctx.coach_org.id

    assert %{"code" => "unknown_provider"} =
             authed(ctx)
             |> put("/api/me/providers/selected", %{organization_id: Ecto.UUID.generate()})
             |> json_response(422)
  end

  test "today merges every provider and survives one failing", ctx do
    Application.put_env(:milos_training, :provider_today, MilosTraining.FlakyProviderToday)
    Application.put_env(:milos_training, :failing_today_providers, [ctx.coach_org.id])

    on_exit(fn ->
      Application.delete_env(:milos_training, :provider_today)
      Application.delete_env(:milos_training, :failing_today_providers)
    end)

    tomorrow = Date.add(Date.utc_today(), 1)
    class!(ctx.box, ctx.owner, ctx.member, DateTime.new!(tomorrow, ~T[10:00:00], "Etc/UTC"))

    body = authed(ctx) |> get("/api/me/today?date=#{tomorrow}") |> json_response(200)
    assert body["partial"] == true
    assert body["failed_organization_ids"] == [ctx.coach_org.id]

    assert [
             %{
               "kind" => "class",
               "title" => "Evening WOD",
               "source" => source,
               "target" => target
             }
           ] =
             Enum.filter(body["items"], &(&1["kind"] == "class"))

    assert source["organization_id"] == ctx.box.id
    assert target["slug"] == ctx.box.slug

    Application.put_env(:milos_training, :failing_today_providers, [])
    body = authed(ctx) |> get("/api/me/today") |> json_response(200)
    assert body["partial"] == false
    assert body["timezone"] == "Etc/UTC"

    assert %{"code" => "invalid_timezone"} =
             authed(ctx) |> get("/api/me/today?timezone=Mars/Base") |> json_response(422)
  end

  test "history, progress and vault span both providers", ctx do
    box_fran = fran!(ctx.owner, ctx.box)
    coach_fran = fran!(ctx.owner, ctx.coach_org)
    execution!(ctx.box, ctx.member, box_fran, -2, 300)
    execution!(ctx.coach_org, ctx.member, coach_fran, -1, 280)

    history = authed(ctx) |> get("/api/me/history?limit=5") |> json_response(200)
    assert history["total"] == 2

    assert Enum.map(history["entries"], & &1["source"]["name"]) == ["Nikos PT", "Box Kypseli"]

    filtered = authed(ctx) |> get("/api/me/history?sources=#{ctx.box.id}") |> json_response(200)
    assert filtered["total"] == 1

    class!(ctx.box, ctx.owner, ctx.member, DateTime.add(DateTime.utc_now(), -2, :day))
    classes = authed(ctx) |> get("/api/me/history?kind=classes") |> json_response(200)

    assert [%{"class" => %{"name" => "Evening WOD"}, "source" => %{"name" => "Box Kypseli"}}] =
             classes["entries"]

    %{"progress" => progress} = authed(ctx) |> get("/api/me/progress") |> json_response(200)
    assert progress["totals"]["sessions"] == 2
    assert [%{"workout_id" => "benchmark:fran", "points" => [_, _]}] = progress["score_history"]

    %{"progress" => narrowed} =
      authed(ctx)
      |> get("/api/me/progress?range=4w&sources=#{ctx.coach_org.id}")
      |> json_response(200)

    assert narrowed["totals"]["sessions"] == 1
    assert narrowed["active_filter_count"] == 2

    vault = authed(ctx) |> get("/api/me/vault?benchmark=fran") |> json_response(200)

    assert [%{"title" => "Fran", "attempt_count" => 2, "attempts" => [latest, older]}] =
             vault["groups"]

    assert latest["source"]["organization_id"] == ctx.coach_org.id

    # «Ξανά» repeats the workout after switching to its provider.
    assert %{"organization_id" => coach_id, "master_workout_id" => coach_workout} = latest
    assert {coach_id, coach_workout} == {ctx.coach_org.id, coach_fran.id}
    assert {older["organization_id"], older["master_workout_id"]} == {ctx.box.id, box_fran.id}

    assert authed(ctx) |> get("/api/me/vault?disciplines=yoga") |> json_response(422)
  end

  test "Ροή filters, «Οι coach μου» and entry audiences", ctx do
    note =
      authed(ctx)
      |> post("/api/me/journal/notes", %{topic: "thought", body: "Easy tempo run"})
      |> json_response(201)
      |> Map.fetch!("note")

    page =
      authed(ctx)
      |> get("/api/me/journal?q=tempo&sources=freeform&remember=true")
      |> json_response(200)

    assert [%{"id" => id, "source" => %{"kind" => "freeform"}, "audience" => audience}] =
             page["items"]

    assert id == note["id"]
    assert Enum.sort(audience["organization_ids"]) == Enum.sort([ctx.box.id, ctx.coach_org.id])
    assert page["active_filter_count"] == 2
    assert page["filter"]["q"] == "tempo"

    remembered = authed(ctx) |> get("/api/me/filters/journal") |> json_response(200)
    assert remembered["last_used"]["sources"] == ["freeform"]

    assert authed(ctx) |> get("/api/me/journal?q=zzzz") |> json_response(200) |> Map.get("items") ==
             []

    # Dates are the member's own days: today in Kiritimati (UTC+14) is
    # never the same calendar day as in Pago Pago (UTC-11).
    day = DateTime.now!("Pacific/Kiritimati") |> DateTime.to_date() |> Date.to_iso8601()
    dated = "/api/me/journal?q=tempo&date_from=#{day}&date_to=#{day}&timezone="

    assert [%{"id" => ^id}] =
             authed(ctx)
             |> get(dated <> "Pacific/Kiritimati")
             |> json_response(200)
             |> Map.get("items")

    assert authed(ctx)
           |> get(dated <> "Pacific/Pago_Pago")
           |> json_response(200)
           |> Map.get("items") ==
             []

    assert %{"code" => "invalid_timezone"} =
             authed(ctx) |> get(dated <> "Mars/Olympus") |> json_response(422)

    # Per coach (ANR, 2026-10-21): the box has two coaches.
    box_coach = user_fixture()
    add!(ctx.box, box_coach, [:coach])
    coach = fn org, user -> %{"organization_id" => org.id, "user_id" => user.id} end

    audience = authed(ctx) |> get("/api/me/journal/coach-audience") |> json_response(200)
    assert [box, nikos] = audience["providers"]
    assert box["included"] and nikos["included"]

    assert Enum.sort(Enum.map(box["coaches"], & &1["user_id"])) ==
             Enum.sort([ctx.owner.id, box_coach.id])

    assert [%{"user_id" => owner_id, "included" => true}] = nikos["coaches"]
    assert owner_id == ctx.owner.id
    assert length(audience["coaches"]) == 3

    narrowed =
      authed(ctx)
      |> put("/api/me/journal/coach-audience", %{coaches: [coach.(ctx.box, box_coach)]})
      |> json_response(200)

    assert narrowed["organization_ids"] == [ctx.box.id]
    assert narrowed["coaches"] == [coach.(ctx.box, box_coach)]

    [box, nikos] = narrowed["providers"]
    assert box["included"] and not nikos["included"]

    assert Map.new(box["coaches"], &{&1["user_id"], &1["included"]}) ==
             %{ctx.owner.id => false, box_coach.id => true}

    # A provider id still means all its coaches.
    assert authed(ctx)
           |> put("/api/me/journal/coach-audience", %{organization_ids: [ctx.box.id]})
           |> json_response(200)
           |> Map.get("coaches")
           |> length() == 2

    shared =
      authed(ctx)
      |> put("/api/me/journal/entries/note/#{note["id"]}/audience", %{
        coaches: [coach.(ctx.coach_org, ctx.owner)]
      })
      |> json_response(200)

    assert shared["audience"] == %{
             "custom" => true,
             "organization_ids" => [ctx.coach_org.id],
             "coaches" => [coach.(ctx.coach_org, ctx.owner)]
           }

    assert %{"code" => "unknown_coach"} =
             authed(ctx)
             |> put("/api/me/journal/entries/note/#{note["id"]}/audience", %{
               coaches: [coach.(ctx.coach_org, box_coach)]
             })
             |> json_response(422)

    moved =
      authed(ctx)
      |> put("/api/me/journal/entries/note/#{note["id"]}/visibility", %{
        visibility: "coach_can_view"
      })
      |> json_response(200)

    assert moved["journal_visibility"] == "coach_can_view"

    assert %{"code" => "empty_audience"} =
             authed(ctx)
             |> put("/api/me/journal/entries/note/#{note["id"]}/audience", %{organization_ids: []})
             |> json_response(422)
  end

  test "export is requested, built and listed with download links", ctx do
    {:ok, _} =
      MilosTraining.Application.JournalNotes.create(
        MilosTraining.Identity.UserContext.new(ctx.member),
        %{"topic" => "mood", "body" => "Export me"}
      )

    %{"export" => export} = authed(ctx) |> post("/api/me/journal/export") |> json_response(202)
    assert export["status"] == "ready"

    assert [%{"name" => "journal.json", "download_url" => url}, %{"name" => "training.csv"}] =
             export["files"]

    assert is_binary(url)

    %{"exports" => [listed]} = authed(ctx) |> get("/api/me/journal/exports") |> json_response(200)
    assert listed["id"] == export["id"]
    assert listed["entry_count"] == 1
  end

  defp org!(name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    Repo.query!("UPDATE organizations SET name = $1 WHERE id = $2", [
      name,
      Ecto.UUID.dump!(organization.id)
    ])

    %{organization | name: name}
  end

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end

  defp class!(organization, owner, member, at) do
    workout = fran!(owner, organization)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    class_type = class_type_fixture(%{tenant_context: context})

    slot =
      Repo.insert!(%MilosTraining.Scheduling.ScheduledClass{
        organization_id: organization.id,
        master_workout_id: workout.id,
        class_type_id: class_type.id,
        name: "Evening WOD",
        scheduled_at: DateTime.truncate(at, :second),
        capacity: 10
      })

    Repo.insert!(%MilosTraining.Scheduling.Booking{
      organization_id: organization.id,
      scheduled_class_id: slot.id,
      user_id: member.id,
      status: :approved
    })
  end

  defp fran!(owner, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    workout_fixture(owner, %{
      tenant_context: context,
      title: "Fran",
      sections: [
        %{
          name: "21-15-9",
          order: 1,
          scoreable: true,
          score_config: %{type: "time"},
          exercises: [
            %{
              name: "Thruster",
              order: 1,
              sets: 1,
              prescription_value: 45,
              prescription_unit: "reps"
            }
          ]
        }
      ]
    })
  end

  defp execution!(organization, member, workout, days, seconds) do
    at = DateTime.add(DateTime.utc_now(), days, :day)

    %WorkoutExecution{organization_id: organization.id}
    |> WorkoutExecution.start_changeset(%{
      user_id: member.id,
      master_workout_id: workout.id,
      source: :self_selected,
      status: :completed,
      started_at_utc: at,
      started_at_tz: "UTC"
    })
    |> Ecto.Changeset.put_change(:completed_at_utc, at)
    |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
    |> Ecto.Changeset.put_change(:total_elapsed_ms, seconds * 1000)
    |> Ecto.Changeset.put_change(:section_scores, [
      %{"section_id" => hd(workout.sections).id, "value" => seconds, "unit" => "s"}
    ])
    |> Repo.insert!()
  end
end
