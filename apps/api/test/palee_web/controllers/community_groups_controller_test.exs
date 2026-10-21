defmodule PaleeWeb.CommunityGroupsControllerTest do
  @moduledoc "ADR-143: member groups, open clubs, «Μέλη», reports and the quiet-group sweep."

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.ArchiveQuietGroups
  alias Palee.Community.Channel
  alias Palee.{Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      admin: person.(:admin),
      coach: person.(:coach),
      member: person.(:member),
      other: person.(:member),
      outsider: user_fixture(),
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{slug}/community",
      staff: "/api/org/#{slug}/admin/community"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp clubs(as, user),
    do: as.(user) |> get("/api/me/clubs") |> json_response(200) |> Map.fetch!("clubs")

  defp gym_club(as, user), do: as |> clubs(user) |> Enum.find(&(&1["kind"] == "gym"))
  defp group_channel(club, id), do: Enum.find(club["channels"], &(&1["id"] == id))

  describe "member groups" do
    test "a proposed group waits for staff, then members join and write in it", ctx do
      %{as: as, base: base, staff: staff, member: member, other: other, coach: coach} = ctx

      assert %{"settings" => %{"member_groups" => "approval", "needs_approval" => true}} =
               as.(member) |> get("#{base}/groups") |> json_response(200)

      assert %{"group" => %{"id" => group_id, "status" => "pending", "admin" => true}} =
               as.(member)
               |> send_json(:post, "#{base}/groups", %{
                 name: "Morning runners",
                 join_policy: "open"
               })
               |> json_response(201)

      # The proposer and staff see it; others don't yet.
      assert %{"status" => "pending", "can_post" => false} =
               group_channel(gym_club(as, member), group_id)

      assert group_channel(gym_club(as, coach), group_id)
      refute group_channel(gym_club(as, other), group_id)
      assert %{"groups" => []} = as.(other) |> get("#{base}/groups") |> json_response(200)

      # Staff see it in «Κοινότητα» and approve it.
      assert %{"pending" => [%{"id" => ^group_id}]} =
               as.(coach) |> get("#{staff}/groups") |> json_response(200)

      assert %{"group" => %{"status" => "active"}} =
               as.(coach)
               |> send_json(:put, "#{staff}/groups/#{group_id}/decision", %{decision: "approve"})
               |> json_response(200)

      # Another member finds it and joins; it reaches their club and they can post.
      assert %{"groups" => [%{"id" => ^group_id, "membership" => "none", "member_count" => 1}]} =
               as.(other) |> get("#{base}/groups") |> json_response(200)

      assert %{"group" => %{"membership" => "member", "member_count" => 2}} =
               as.(other) |> post("#{base}/groups/#{group_id}/membership") |> json_response(200)

      assert %{"participant" => true, "can_post" => true} =
               group_channel(gym_club(as, other), group_id)

      assert %{"post" => %{"id" => post_id}} =
               as.(other)
               |> send_json(:post, "#{base}/posts", %{channel_id: group_id, body: "6am tomorrow?"})
               |> json_response(201)

      # Staff moderate but don't write in a group they're not in.
      assert %{"code" => "cannot_post_in_channel"} =
               as.(coach)
               |> send_json(:post, "#{base}/posts", %{channel_id: group_id, body: "Hi"})
               |> json_response(403)

      # The group's admin hides a post in their group.
      assert %{"post" => %{"hidden" => true}} =
               as.(member)
               |> send_json(:put, "#{base}/posts/#{post_id}/hidden", %{hidden: true})
               |> json_response(200)

      # A post keeps the group alive.
      assert %Channel{last_post_at: %DateTime{}} = Repo.get(Channel, group_id)
    end

    test "a group that asks: requests, admins, handing over and the last one out", ctx do
      %{as: as, base: base, member: member, other: other, coach: coach} = ctx

      # Staff start groups that need no approval.
      assert %{"group" => %{"id" => group_id, "status" => "active"}} =
               as.(coach)
               |> send_json(:post, "#{base}/groups", %{name: "Lifters", join_policy: "request"})
               |> json_response(201)

      assert %{"group" => %{"membership" => "requested"}} =
               as.(member) |> post("#{base}/groups/#{group_id}/membership") |> json_response(200)

      # Until let in, it isn't in their club; the list shows the request.
      refute group_channel(gym_club(as, member), group_id)

      assert %{"groups" => [%{"id" => ^group_id, "membership" => "requested"}]} =
               as.(member) |> get("#{base}/groups") |> json_response(200)

      # A member can't answer; the admin can.
      assert as.(other)
             |> send_json(:put, "#{base}/groups/#{group_id}/requests/#{member.id}", %{
               approve: true
             })
             |> json_response(403)

      assert %{"group" => %{"members" => members}} =
               as.(coach)
               |> send_json(:put, "#{base}/groups/#{group_id}/requests/#{member.id}", %{
                 approve: true
               })
               |> json_response(200)

      assert Enum.any?(members, &(&1["person"]["id"] == member.id and &1["status"] == "member"))

      # The only admin hands over before leaving.
      assert %{"code" => "hand_over_first"} =
               as.(coach) |> delete("#{base}/groups/#{group_id}/membership") |> json_response(422)

      assert %{"group" => _group} =
               as.(coach)
               |> send_json(:put, "#{base}/groups/#{group_id}/admins/#{member.id}", %{admin: true})
               |> json_response(200)

      assert %{"outcome" => "left"} =
               as.(coach) |> delete("#{base}/groups/#{group_id}/membership") |> json_response(200)

      assert %{"outcome" => "archived"} =
               as.(member)
               |> delete("#{base}/groups/#{group_id}/membership")
               |> json_response(200)

      assert %Channel{archived_at: %DateTime{}} = Repo.get(Channel, group_id)

      # The member who left last didn't start it; its creator (the coach) can reopen it.
      assert as.(other) |> post("#{base}/groups/#{group_id}/reopen") |> json_response(403)

      assert %{"archived" => [%{"id" => ^group_id}]} =
               as.(coach) |> get("#{base}/groups") |> json_response(200)

      assert %{"group" => %{"archived_at" => nil, "admin" => true, "membership" => "member"}} =
               as.(coach) |> post("#{base}/groups/#{group_id}/reopen") |> json_response(200)
    end

    test "the owner's rule decides who may start groups", ctx do
      %{as: as, base: base, staff: staff, admin: admin, coach: coach, member: member} = ctx

      assert as.(coach)
             |> send_json(:put, "#{staff}/settings", %{member_groups: "none"})
             |> json_response(403)

      assert %{"member_groups" => "none"} =
               as.(admin)
               |> send_json(:put, "#{staff}/settings", %{member_groups: "none"})
               |> json_response(200)

      assert %{"code" => "member_groups_disabled"} =
               as.(member)
               |> send_json(:post, "#{base}/groups", %{name: "Nope"})
               |> json_response(403)

      assert %{"member_groups" => "free"} =
               as.(admin)
               |> send_json(:put, "#{staff}/settings", %{member_groups: "free"})
               |> json_response(200)

      assert %{"group" => %{"status" => "active"}} =
               as.(member)
               |> send_json(:post, "#{base}/groups", %{name: "Free group"})
               |> json_response(201)

      # Names are unique per club, whatever the case.
      assert as.(member)
             |> send_json(:post, "#{base}/groups", %{name: "free GROUP"})
             |> json_response(422)
    end

    test "quiet groups are warned at 50 days and archived ten days after", ctx do
      %{as: as, base: base, coach: coach} = ctx

      assert %{"group" => %{"id" => group_id}} =
               as.(coach)
               |> send_json(:post, "#{base}/groups", %{name: "Sleepy"})
               |> json_response(201)

      now = DateTime.utc_now()
      quiet_since = DateTime.add(now, -51, :day)

      Repo.update_all(from(c in Channel, where: c.id == ^group_id),
        set: [last_post_at: quiet_since, decided_at: quiet_since]
      )

      ArchiveQuietGroups.call(now)

      assert %Channel{archive_warned_at: %DateTime{}, archived_at: nil} =
               Repo.get(Channel, group_id)

      Repo.update_all(from(c in Channel, where: c.id == ^group_id),
        set: [last_post_at: DateTime.add(now, -61, :day)]
      )

      ArchiveQuietGroups.call(now)
      assert %Channel{archived_at: %DateTime{}} = Repo.get(Channel, group_id)

      # Its creator sees it among their archived groups and can bring it back too.
      assert %{"archived" => [%{"id" => ^group_id}]} =
               as.(coach) |> get("#{base}/groups") |> json_response(200)

      # Its creator sees it among their archived groups; staff bring it back.
      assert %{"archived" => [%{"id" => ^group_id}]} =
               as.(coach) |> get("#{ctx.staff}/groups") |> json_response(200)

      assert %{"group" => %{"archived_at" => nil}} =
               as.(coach) |> post("#{ctx.staff}/groups/#{group_id}/reopen") |> json_response(200)
    end
  end

  describe "reports" do
    test "a report hides the item for the reporter and staff act once for every report", ctx do
      %{as: as, base: base, staff: staff, member: member, other: other, coach: coach} = ctx
      wod = Enum.find(gym_club(as, member)["channels"], &(&1["kind"] == "wod"))

      assert %{"post" => %{"id" => post_id, "can_report" => false}} =
               as.(member)
               |> send_json(:post, "#{base}/posts", %{channel_id: wod["id"], body: "Buy my stuff"})
               |> json_response(201)

      assert %{"code" => "cannot_report_own"} =
               as.(member)
               |> send_json(:post, "/api/me/community/reports", %{
                 target_type: "post",
                 target_id: post_id,
                 reason: "spam"
               })
               |> json_response(422)

      report = %{target_type: "post", target_id: post_id, reason: "spam", note: "Ads"}

      assert %{"reported" => true} =
               as.(other)
               |> send_json(:post, "/api/me/community/reports", report)
               |> json_response(201)

      # Twice is fine.
      assert %{"reported" => true} =
               as.(other)
               |> send_json(:post, "/api/me/community/reports", report)
               |> json_response(201)

      %{"posts" => posts} = as.(other) |> get("/api/me/feed") |> json_response(200)
      refute Enum.any?(posts, &(&1["id"] == post_id))

      assert %{"reports" => [%{"target_id" => ^post_id, "report_count" => 1} = row]} =
               as.(coach) |> get("#{staff}/reports") |> json_response(200)

      assert row["reasons"] == %{"spam" => 1}
      assert row["notes"] == ["Ads"]
      assert row["author"]["id"] == member.id

      assert as.(member) |> get("#{staff}/reports") |> json_response(403)

      assert %{"resolved" => 1} =
               as.(coach)
               |> send_json(:post, "#{staff}/reports/actions", %{
                 target_type: "post",
                 target_id: post_id,
                 action: "hide"
               })
               |> json_response(200)

      assert %{"reports" => []} = as.(coach) |> get("#{staff}/reports") |> json_response(200)

      assert %{"code" => "invalid_action"} =
               as.(coach)
               |> send_json(:post, "#{staff}/reports/actions", %{
                 target_type: "post",
                 target_id: post_id,
                 action: "archive"
               })
               |> json_response(422)
    end

    test "comments can be reported and hidden", ctx do
      %{as: as, base: base, staff: staff, member: member, other: other, coach: coach} = ctx
      wod = Enum.find(gym_club(as, member)["channels"], &(&1["kind"] == "wod"))

      %{"post" => %{"id" => post_id}} =
        as.(member)
        |> send_json(:post, "#{base}/posts", %{channel_id: wod["id"], body: "Fran"})
        |> json_response(201)

      %{"comment" => %{"id" => comment_id}} =
        as.(other)
        |> send_json(:post, "#{base}/posts/#{post_id}/comments", %{body: "rude"})
        |> json_response(201)

      as.(member)
      |> send_json(:post, "/api/me/community/reports", %{
        target_type: "comment",
        target_id: comment_id,
        reason: "harassment"
      })
      |> json_response(201)

      assert %{"comments" => []} =
               as.(member) |> get("#{base}/posts/#{post_id}/comments") |> json_response(200)

      as.(coach)
      |> send_json(:post, "#{staff}/reports/actions", %{
        target_type: "comment",
        target_id: comment_id,
        action: "hide"
      })
      |> json_response(200)

      # Hidden: its author and staff still see it, marked.
      assert %{"comments" => [%{"hidden" => true}]} =
               as.(other) |> get("#{base}/posts/#{post_id}/comments") |> json_response(200)

      assert %{"comments" => [%{"hidden" => true, "can_moderate" => true}]} =
               as.(coach) |> get("#{base}/posts/#{post_id}/comments") |> json_response(200)
    end
  end

  describe "open clubs" do
    test "staff start one; anyone finds it, asks to join, and posts once let in", ctx do
      %{as: as, staff: staff, admin: admin, coach: coach, outsider: outsider} = ctx

      assert as.(coach)
             |> send_json(:post, "#{staff}/clubs", %{name: "Saturday trail runs"})
             |> json_response(403)

      assert %{"club" => %{"id" => club_id, "join_policy" => "approval"}} =
               as.(admin)
               |> send_json(:post, "#{staff}/clubs", %{
                 name: "Saturday trail runs",
                 description: "Every Saturday, all paces",
                 join_policy: "approval"
               })
               |> json_response(201)

      # Members of the gym find it in «Βρες»; someone from outside opens it
      # from the box page.
      assert %{"clubs" => [%{"id" => ^club_id, "membership" => "none", "member_count" => 0}]} =
               as.(ctx.member)
               |> get("/api/me/community/discover?q=trail")
               |> json_response(200)

      assert %{"clubs" => []} =
               as.(outsider) |> get("/api/me/community/discover") |> json_response(200)

      assert %{"club" => %{"name" => "Saturday trail runs", "membership" => "none"}} =
               as.(outsider) |> get("/api/me/open-clubs/#{club_id}") |> json_response(200)

      assert %{"club" => %{"membership" => "requested"}} =
               as.(outsider)
               |> post("/api/me/open-clubs/#{club_id}/membership")
               |> json_response(200)

      assert [] == clubs(as, outsider)

      assert %{"club" => %{"requests" => [%{"person" => %{"id" => outsider_id}}]}} =
               as.(coach) |> get("#{staff}/clubs/#{club_id}") |> json_response(200)

      assert outsider_id == outsider.id

      assert %{"club" => %{"member_count" => 1, "requests" => []}} =
               as.(coach)
               |> send_json(:put, "#{staff}/clubs/#{club_id}/requests/#{outsider.id}", %{
                 approve: true
               })
               |> json_response(200)

      # Now it's their club: it has announcements and a general channel they write in.
      assert [%{"id" => ^club_id, "kind" => "open", "role" => "member"} = club] =
               clubs(as, outsider)

      general = Enum.find(club["channels"], &(&1["kind"] == "general"))
      assert general["can_post"]

      assert %{"post" => %{"id" => _post_id, "club" => %{"id" => ^club_id}}} =
               as.(outsider)
               |> send_json(:post, "/api/me/community/posts", %{
                 channel_id: general["id"],
                 body: "See you at 8"
               })
               |> json_response(201)

      assert %{"posts" => [%{"body" => "See you at 8"}]} =
               as.(outsider) |> get("/api/me/feed?club_id=#{club_id}") |> json_response(200)

      # Staff of the gym see the club in their bar too.
      assert Enum.any?(clubs(as, coach), &(&1["id"] == club_id and &1["role"] == "staff"))

      assert %{"members" => [%{"id" => ^outsider_id}]} =
               as.(coach) |> get("/api/me/clubs/#{club_id}/members") |> json_response(200)

      assert %{"notify_level" => "none"} =
               as.(outsider)
               |> send_json(:put, "/api/me/open-clubs/#{club_id}/notify-level", %{
                 notify_level: "none"
               })
               |> json_response(200)

      assert %{"club" => %{"membership" => "none"}} =
               as.(outsider)
               |> delete("/api/me/open-clubs/#{club_id}/membership")
               |> json_response(200)

      assert [] == clubs(as, outsider)
    end
  end

  test "«Μέλη» lists the club's people without the viewer, coaches first", ctx do
    %{as: as, member: member, coach: coach, other: other} = ctx
    club = gym_club(as, member)

    assert %{"members" => members} =
             as.(member) |> get("/api/me/clubs/#{club["id"]}/members") |> json_response(200)

    ids = Enum.map(members, & &1["id"])
    refute member.id in ids
    assert other.id in ids
    assert %{"coach" => true} = Enum.find(members, &(&1["id"] == coach.id))
    assert hd(members)["coach"]

    assert as.(ctx.outsider) |> get("/api/me/clubs/#{club["id"]}/members") |> json_response(404)

    # Board 7 Q1: someone can keep out of «Μέλη».
    assert %{"hidden" => true} =
             as.(other)
             |> send_json(:put, "/api/me/social/member-visibility", %{hidden: true})
             |> json_response(200)

    assert %{"member_visibility" => %{"hidden" => true}} =
             as.(other) |> get("/api/me/social") |> json_response(200)

    %{"members" => members} =
      as.(member) |> get("/api/me/clubs/#{club["id"]}/members") |> json_response(200)

    refute Enum.any?(members, &(&1["id"] == other.id))
  end
end
