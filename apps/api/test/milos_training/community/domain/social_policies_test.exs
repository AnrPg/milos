defmodule MilosTraining.Community.Domain.SocialPoliciesTest do
  @moduledoc "ADR-142: who starts a follow as a request, and who may post publicly."

  use ExUnit.Case, async: true

  alias MilosTraining.Community.Domain.{AudiencePolicy, FollowPolicy}

  test "a person is followed by request, a box or club at once" do
    assert FollowPolicy.initial_status("user") == "requested"
    assert FollowPolicy.initial_status("organization") == "active"
    assert FollowPolicy.status(nil) == "none"
  end

  test "follow targets are checked" do
    me = Ecto.UUID.generate()
    assert {:error, :cannot_follow_self} = FollowPolicy.check(me, "user", %{id: me})
    assert {:error, :invalid_follow_target} = FollowPolicy.check(me, "planet", %{id: me})
    assert {:error, :not_found} = FollowPolicy.check(me, "user", nil)
    assert {:error, :not_found} = FollowPolicy.check(me, "club", %{id: me, kind: "gym"})
    assert :ok = FollowPolicy.check(me, "user", %{id: Ecto.UUID.generate()})
  end

  test "only staff make a club post public; profile posts go to followers or everyone" do
    assert AudiencePolicy.club_audience_allowed?("club_channel", "member")
    refute AudiencePolicy.club_audience_allowed?("public", "member")
    assert AudiencePolicy.club_audience_allowed?("public", "staff")
    refute AudiencePolicy.club_audience_allowed?("followers", "staff")
    assert AudiencePolicy.profile_audience?("followers")
    refute AudiencePolicy.profile_audience?("club_channel")
  end
end
