defmodule MilosTraining.Organizations.Domain.MembershipPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.MembershipPolicy

  test "keeps tenant roles distinct from membership lifecycle" do
    assert MembershipPolicy.roles() == [:owner, :admin, :coach, :member, :athlete]
    assert MembershipPolicy.statuses() == [:invited, :active, :suspended, :revoked]
  end

  test "only active memberships authorize tenant access" do
    assert MembershipPolicy.authorized_status?(:active)
    refute MembershipPolicy.authorized_status?(:invited)
    refute MembershipPolicy.authorized_status?(:suspended)
    refute MembershipPolicy.authorized_status?(:revoked)
  end

  test "only organization owners and admins may manage invitations" do
    assert MembershipPolicy.can_manage_invitations?(:owner)
    assert MembershipPolicy.can_manage_invitations?(:admin)
    refute MembershipPolicy.can_manage_invitations?(:coach)
    refute MembershipPolicy.can_manage_invitations?(:member)
  end
end
