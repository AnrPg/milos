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

  # The "only owners and admins may manage invitations" rule used to be
  # asserted here against can_manage_invitations?/1, which nothing called. It
  # is now asserted against the live paths instead - see
  # organizations_test.exs ("a member cannot issue invitations") and
  # set_membership_role_test.exs ("a coach cannot change roles at all").
end
