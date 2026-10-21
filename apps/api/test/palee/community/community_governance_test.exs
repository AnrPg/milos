defmodule Palee.Community.CommunityGovernanceTest do
  @moduledoc "ADR-143: the pure rules for member groups, open clubs and reports."

  use ExUnit.Case, async: true

  alias Palee.Community.Domain.{ChannelPolicy, ClubPolicy, GroupPolicy, ReportPolicy}
  alias Palee.Notifications.Domain.PushMessageBuilder

  describe "GroupPolicy" do
    test "the owner's rule decides who starts groups and whether they wait" do
      assert GroupPolicy.can_propose?("staff", "none")
      refute GroupPolicy.can_propose?("member", "none")
      assert GroupPolicy.can_propose?("member", "approval")

      assert GroupPolicy.initial_status("member", "approval") == "pending"
      assert GroupPolicy.initial_status("member", "free") == "active"
      assert GroupPolicy.initial_status("staff", "approval") == "active"
    end

    test "leaving: the last admin hands over, the last member archives" do
      assert {:error, :hand_over_first} = GroupPolicy.on_leave(%{role: "admin"}, 1, 3)
      assert :leave = GroupPolicy.on_leave(%{role: "admin"}, 2, 3)
      assert :leave = GroupPolicy.on_leave(%{role: "member"}, 1, 3)
      assert :archive = GroupPolicy.on_leave(%{role: "admin"}, 1, 1)
    end

    test "a quiet group is warned at 50 days and archived at 60 once warned" do
      now = ~U[2026-10-20 04:20:00Z]

      group = fn days, warned ->
        %{
          last_post_at: DateTime.add(now, -days, :day),
          decided_at: nil,
          inserted_at: nil,
          archive_warned_at: warned
        }
      end

      assert :none = GroupPolicy.quiet_step(group.(49, nil), now)
      assert :warn = GroupPolicy.quiet_step(group.(50, nil), now)
      assert :none = GroupPolicy.quiet_step(group.(55, now), now)
      assert :archive = GroupPolicy.quiet_step(group.(60, now), now)
      # Never archived without a warning first.
      assert :warn = GroupPolicy.quiet_step(group.(70, nil), now)
    end
  end

  test "ChannelPolicy: proposed groups are read-only and only members write in a group" do
    group = %{
      kind: "member_group",
      write_policy: "participants",
      status: "active",
      archived_at: nil
    }

    refute ChannelPolicy.can_post?(%{group | status: "pending"}, "staff", true)
    refute ChannelPolicy.can_post?(group, "staff", false)
    assert ChannelPolicy.can_post?(group, "member", true)

    assert ChannelPolicy.channel_role("member", Map.put(group, :admin, true)) == "staff"
    assert ChannelPolicy.channel_role("member", Map.put(group, :admin, false)) == "member"
    assert ChannelPolicy.can_pin?(group, "staff")
  end

  test "ClubPolicy: approval clubs wait, open clubs let in" do
    assert ClubPolicy.join_status(%{join_policy: "open"}) == "active"
    assert ClubPolicy.join_status(%{join_policy: "approval"}) == "pending"
    assert ClubPolicy.role("staff", nil) == "staff"
    assert ClubPolicy.role("member", "active") == "member"
    assert ClubPolicy.role("member", "pending") == nil
  end

  test "ReportPolicy: actions fit their targets and nobody reports themselves" do
    assert {:ok, {"actioned", "hidden"}} = ReportPolicy.resolve("hide", "post")
    assert {:ok, {"actioned", "archived"}} = ReportPolicy.resolve("archive", "channel")
    assert {:ok, {"dismissed", "none"}} = ReportPolicy.resolve("dismiss", "comment")
    assert {:error, :invalid_action} = ReportPolicy.resolve("archive", "post")
    refute ReportPolicy.can_report?(%{author_id: "a"}, "a")
    assert ReportPolicy.can_report?(%{author_id: "a"}, "b")
  end

  test "every community notification has push copy" do
    for type <-
          ~w(community_group_proposed community_group_approved community_group_declined community_group_join_requested community_group_join_approved community_group_archive_warning community_report_created community_club_join_requested community_club_join_approved) do
      message =
        PushMessageBuilder.build(type, %{
          "group_name" => "Runners",
          "club_name" => "Trail",
          "person_nickname" => "ana"
        })

      assert is_binary(message.title) and message.title != ""
      refute message.body =~ "%{"
    end
  end
end
