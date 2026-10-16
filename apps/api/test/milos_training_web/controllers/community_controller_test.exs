defmodule MilosTrainingWeb.CommunityControllerTest do
  @moduledoc "ADR-138: the gym club, its channels' governance, posts, kudos, comments and moderation."

  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Community, Organizations, Repo}

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

  defp rung(entry_id) do
    %{rows: [[rung]]} =
      Repo.query!("SELECT journal_visibility FROM training_log_entries WHERE id = $1", [
        Ecto.UUID.dump!(entry_id)
      ])

    rung
  end
end
