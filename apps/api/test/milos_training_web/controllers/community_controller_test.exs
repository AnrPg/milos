defmodule MilosTrainingWeb.CommunityControllerTest do
  @moduledoc "ADR-138: the gym club, its channels' governance, posts, kudos, comments and moderation."

  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Community, Organizations, Repo}
  alias MilosTraining.Gamification.GamificationStore
  alias MilosTraining.Application.SyncClassGroups

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    %{
      organization: organization,
      coach: person.(:coach),
      member: person.(:member),
      other: person.(:member),
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{Organizations.legacy_organization_slug()}/community"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp club(as, user) do
    assert %{"clubs" => [club]} = as.(user) |> get("/api/me/clubs") |> json_response(200)
    club
  end

  defp channel(club, kind), do: Enum.find(club["channels"], &(&1["kind"] == kind))

  test "a gym's club is provisioned on first read with its built-in channels", ctx do
    club = club(ctx.as, ctx.member)

    assert club["kind"] == "gym"
    assert club["role"] == "member"
    assert club["notify_level"] == "all"

    assert [
             %{
               "kind" => "announcements",
               "joined" => true,
               "can_post" => false,
               "can_leave" => false
             },
             %{"kind" => "wod", "joined" => true, "can_post" => true},
             %{
               "kind" => "challenges",
               "joined" => false,
               "can_post" => false,
               "can_leave" => true
             }
           ] = club["channels"]

    assert %{"role" => "staff"} = club(ctx.as, ctx.coach)

    # Provisioning again changes nothing.
    {:ok, again} = Community.provision_gym_club(%{organization_id: ctx.organization.id})
    assert again.id == club["id"]
    assert length(again.channels) == 3
  end

  test "notification level and opt-in channels", ctx do
    %{as: as, base: base, member: member} = ctx
    club = club(as, member)

    assert %{"notify_level" => "announcements"} =
             as.(member)
             |> send_json(:put, "#{base}/clubs/#{club["id"]}/notify-level", %{
               notify_level: "announcements"
             })
             |> json_response(200)

    challenges = channel(club, "challenges")

    assert %{"joined" => true} =
             as.(member)
             |> post("#{base}/channels/#{challenges["id"]}/membership")
             |> json_response(200)

    club = club(as, member)
    assert club["notify_level"] == "announcements"
    assert %{"joined" => true, "can_post" => true} = channel(club, "challenges")

    assert %{"code" => "channel_not_optional"} =
             as.(member)
             |> post("#{base}/channels/#{channel(club, "announcements")["id"]}/membership")
             |> json_response(422)

    assert %{"joined" => false} =
             as.(member)
             |> delete("#{base}/channels/#{challenges["id"]}/membership")
             |> json_response(200)
  end

  test "posting follows channel governance and reaches the feed with its origin", ctx do
    %{as: as, base: base, coach: coach, member: member, other: other} = ctx
    club = club(as, member)
    announcements = channel(club, "announcements")
    wod = channel(club, "wod")

    assert %{"code" => "cannot_post_in_channel"} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{channel_id: announcements["id"], body: "Hi"})
             |> json_response(403)

    assert %{"post" => %{"id" => notice_id, "can_pin" => true}} =
             as.(coach)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: announcements["id"],
               body: "Closed on Tuesday"
             })
             |> json_response(201)

    body = %{channel_id: wod["id"], body: "Fran 4:12!", client_operation_id: "op-1"}

    assert %{"post" => %{"id" => post_id} = post} =
             as.(member) |> send_json(:post, "#{base}/posts", body) |> json_response(201)

    assert post["channel"]["kind"] == "wod"
    assert post["club"]["name"] == club["name"]
    assert post["author"]["id"] == member.id

    # The outbox replays the same operation: same post.
    assert %{"post" => %{"id" => ^post_id}} =
             as.(member) |> send_json(:post, "#{base}/posts", body) |> json_response(201)

    assert %{"post" => %{"pinned" => true}} =
             as.(coach)
             |> send_json(:put, "#{base}/posts/#{notice_id}/pinned", %{pinned: true})
             |> json_response(200)

    assert %{"pinned" => [%{"id" => ^notice_id}], "posts" => [%{"id" => ^post_id}]} =
             as.(other) |> get("/api/me/feed") |> json_response(200)

    assert %{"post" => %{"kudos_count" => 1, "kudos_by_me" => true}} =
             as.(other)
             |> send_json(:put, "#{base}/posts/#{post_id}/kudos", %{kudos: true})
             |> json_response(200)

    assert %{"comment" => %{"id" => comment_id, "can_delete" => true}} =
             as.(other)
             |> send_json(:post, "#{base}/posts/#{post_id}/comments", %{body: "Bravo"})
             |> json_response(201)

    assert %{"comments" => [%{"id" => ^comment_id, "can_delete" => false}]} =
             as.(member) |> get("#{base}/posts/#{post_id}/comments") |> json_response(200)

    assert %{"posts" => [%{"id" => ^post_id, "comment_count" => 1}]} =
             as.(member) |> get("/api/me/feed?mine=true") |> json_response(200)

    # D8: staff hide; the author still sees it, others do not.
    as.(coach)
    |> send_json(:put, "#{base}/posts/#{post_id}/hidden", %{hidden: true})
    |> json_response(200)

    assert %{"posts" => []} = as.(other) |> get("/api/me/feed") |> json_response(200)

    assert %{"posts" => [%{"id" => ^post_id, "hidden" => true}]} =
             as.(member) |> get("/api/me/feed") |> json_response(200)

    assert as.(other) |> delete("#{base}/posts/#{post_id}") |> response(404)
    assert as.(member) |> delete("#{base}/posts/#{post_id}") |> response(204)
    assert %{"posts" => []} = as.(member) |> get("/api/me/feed") |> json_response(200)
  end

  test "attaching a journal entry snapshots it and moves it to posted", ctx do
    %{as: as, base: base, member: member} = ctx
    wod = channel(club(as, member), "wod")

    assert %{"entry" => %{"id" => entry_id}} =
             as.(member)
             |> send_json(
               :post,
               "/api/org/#{Organizations.legacy_organization_slug()}/me/training-log/entries",
               %{
                 source_type: "freeform",
                 title: "Beach workout",
                 performed_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
                 timezone: "Europe/Athens",
                 duration_seconds: 1800,
                 idempotency_key: "community-" <> Ecto.UUID.generate(),
                 performed_exercises: [%{name: "Sprint", sets: 4}]
               }
             )
             |> json_response(201)

    assert %{"post" => %{"id" => post_id, "attachment" => attachment}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod["id"],
               attachment_type: "training_log_entry",
               attachment_id: entry_id
             })
             |> json_response(201)

    assert attachment["title"] == "Beach workout"
    refute Map.has_key?(attachment, "previous_visibility")
    assert rung(entry_id) == "posted"

    assert as.(member) |> delete("#{base}/posts/#{post_id}") |> response(204)
    assert rung(entry_id) == "coach_can_view"

    assert %{"code" => "attachment_not_shareable"} =
             as.(ctx.other)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod["id"],
               attachment_type: "training_log_entry",
               attachment_id: entry_id
             })
             |> json_response(422)
  end

  test "class groups follow the schedule and are offered to regulars", ctx do
    %{as: as, base: base, member: member, other: other, organization: organization} = ctx
    context = %{organization_id: organization.id}
    series = %{id: Ecto.UUID.generate(), name: "CrossFit", local_start_time: ~T[18:30:00]}

    assert {:ok, %{channels: 1, suggestions: 1}} =
             Community.sync_class_groups(context, [series], [
               %{series_id: series.id, user_id: member.id, count: 3},
               %{series_id: series.id, user_id: other.id, count: 2}
             ])

    group = channel(club(as, member), "class_slot")

    assert %{
             "name" => "CrossFit 18:30",
             "suggested" => true,
             "participant" => false,
             "joined" => false,
             "can_leave" => true
           } = group

    assert %{"suggested" => false} = channel(club(as, other), "class_slot")

    as.(member) |> post("#{base}/channels/#{group["id"]}/membership") |> json_response(200)

    assert %{"participant" => true, "suggested" => false} =
             channel(club(as, member), "class_slot")

    # Leaving remembers the choice: a later sync does not offer it again.
    as.(member) |> delete("#{base}/channels/#{group["id"]}/membership") |> json_response(200)

    {:ok, _} =
      Community.sync_class_groups(context, [series], [
        %{series_id: series.id, user_id: member.id, count: 5}
      ])

    assert %{"suggested" => false, "participant" => false} =
             channel(club(as, member), "class_slot")

    # A class that no longer runs has its group archived.
    assert {:ok, %{channels: 0}} = SyncClassGroups.call(context)
    assert channel(club(as, member), "class_slot") == nil
  end

  test "entering a challenge joins the #challenges channel", ctx do
    %{as: as, member: member, organization: organization, coach: coach} = ctx
    slug = Organizations.legacy_organization_slug()

    {:ok, challenge} =
      GamificationStore.with_tenant_context(%{organization_id: organization.id}, fn ->
        GamificationStore.create_challenge(%{
          organization_id: organization.id,
          title: "October Push",
          description: "Community challenge",
          criteria_type: :workout_count,
          criteria_value: %{count: 3},
          badge_key: "october-push-#{System.unique_integer([:positive])}",
          badge_label: "October Push",
          starts_at: Date.utc_today(),
          ends_at: Date.add(Date.utc_today(), 30),
          created_by_id: coach.id
        })
      end)

    assert %{"participant" => false} = channel(club(as, member), "challenges")

    as.(member)
    |> post("/api/org/#{slug}/challenges/#{challenge.id}/opt_in")
    |> json_response(200)

    assert %{"participant" => true, "joined" => true, "can_post" => true} =
             channel(club(as, member), "challenges")
  end

  test "the #wod card ranks today's results of members who opted in", ctx do
    %{as: as, base: base, member: member, other: other, coach: coach} = ctx
    slug = Organizations.legacy_organization_slug()

    assert %{"workout" => nil, "leaderboard" => [], "logged_by_me" => false} =
             as.(member) |> get("#{base}/wod-today?timezone=Etc/UTC") |> json_response(200)

    workout =
      workout_fixture(coach, %{
        title: "Fran",
        sections: [
          %{
            name: "For time",
            order: 1,
            scoreable: true,
            score_config: %{type: "time"},
            exercises: [%{name: "Thrusters", order: 1, prescription_value: 21}]
          }
        ]
      })

    section = hd(workout.sections)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    slot = slot_fixture(workout)

    # Classes are created in the future; move this one to earlier today.
    Repo.query!("UPDATE scheduled_classes SET scheduled_at = $1 WHERE id = $2", [
      DateTime.add(now, -120),
      Ecto.UUID.dump!(slot.id)
    ])

    log = fn user, time ->
      as.(user)
      |> send_json(:post, "/api/org/#{slug}/me/training-log/entries", %{
        source_type: "library_workout",
        source_reference_id: workout.id,
        performed_at: now |> DateTime.add(-60) |> DateTime.to_iso8601(),
        timezone: "Etc/UTC",
        idempotency_key: "wod-" <> Ecto.UUID.generate(),
        section_scores: [%{section_id: section.id, value: time}]
      })
      |> json_response(201)
    end

    log.(member, "4:10")
    log.(other, "3:05")

    card = as.(member) |> get("#{base}/wod-today?timezone=Etc/UTC") |> json_response(200)
    assert %{"workout" => %{"title" => "Fran"}, "logged_by_me" => true} = card
    assert %{"score_type" => "time"} = card["score"]
    assert [_class] = card["classes"]

    # Only the viewer's own row until the others opt in to leaderboards.
    assert [%{"rank" => 1, "me" => true, "value" => "4:10", "opted_in" => false}] =
             card["leaderboard"]

    as.(other)
    |> send_json(:post, "/api/org/#{slug}/landing/leaderboard-opt-in", %{opted_in: true})
    |> json_response(200)

    assert [
             %{"rank" => 1, "me" => false, "value" => "3:05"},
             %{"rank" => 2, "me" => true}
           ] =
             as.(member)
             |> get("#{base}/wod-today?timezone=Etc/UTC")
             |> json_response(200)
             |> Map.fetch!("leaderboard")

    assert %{"code" => "invalid_timezone"} =
             as.(member) |> get("#{base}/wod-today?timezone=Mars/Base") |> json_response(422)
  end

  defp rung(entry_id) do
    %{rows: [[rung]]} =
      Repo.query!("SELECT journal_visibility FROM training_log_entries WHERE id = $1", [
        Ecto.UUID.dump!(entry_id)
      ])

    rung
  end
end
