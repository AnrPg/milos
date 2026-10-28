defmodule Palee.Organizations.Domain.MembershipPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.MembershipPolicy

  test "keeps tenant roles distinct from membership lifecycle" do
    assert MembershipPolicy.roles() == [
             :owner,
             :admin,
             :coach,
             :front_desk,
             :accountant,
             :janitor,
             :member,
             :athlete
           ]

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

  describe "the role hierarchy (ADR-219)" do
    test "ranks owner over admin over staff over clients; a tier's roles are peers" do
      assert MembershipPolicy.tier(:owner) > MembershipPolicy.tier(:admin)
      assert MembershipPolicy.tier(:admin) > MembershipPolicy.tier(:coach)

      for staff <- [:front_desk, :accountant, :janitor],
          do: assert(MembershipPolicy.tier(staff) == MembershipPolicy.tier(:coach))

      assert MembershipPolicy.tier(:coach) > MembershipPolicy.tier(:member)
      assert MembershipPolicy.tier(:member) == MembershipPolicy.tier(:athlete)
      assert MembershipPolicy.top_tier([:member, :admin]) == MembershipPolicy.tier(:admin)
      assert MembershipPolicy.top_tier([]) == 0
    end

    test "people act only on those ranked below them; owners also on co-owners" do
      assert MembershipPolicy.can_manage_member?([:admin], [:coach, :member])
      refute MembershipPolicy.can_manage_member?([:admin], [:admin])
      refute MembershipPolicy.can_manage_member?([:admin, :coach], [:owner, :member])
      refute MembershipPolicy.can_manage_member?([:coach], [:front_desk])
      assert MembershipPolicy.can_manage_member?([:coach], [:athlete])
      assert MembershipPolicy.can_manage_member?([:owner], [:owner, :coach])
    end

    test "on someone else every changed role must be grantable and the target ranked below" do
      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:member],
                 [:coach, :member],
                 :other
               )

      # Lower roles of a fellow admin or of an owner are out of reach.
      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:admin],
                 [:admin, :coach],
                 :other
               )

      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:owner, :member],
                 [:owner],
                 :other
               )

      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change([:admin], [:coach], [:admin], :other)

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:owner],
                 [:owner, :coach],
                 [:admin],
                 :other
               )
    end

    test "on oneself only roles below the top role move" do
      assert :ok =
               MembershipPolicy.authorize_role_change([:owner], [:owner], [:owner, :coach], :self)

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:owner, :coach],
                 [:owner, :coach],
                 [:owner, :member],
                 :self
               )

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:coach],
                 [:coach],
                 [:coach, :member],
                 :self
               )

      # The top role never changes, nor does a peer of it.
      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change([:owner], [:owner], [:coach], :self)

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change([:admin], [:admin], [:admin, :owner], :self)

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change(
                 [:coach],
                 [:coach],
                 [:coach, :front_desk],
                 :self
               )

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change(
                 [:member],
                 [:member],
                 [:member, :athlete],
                 :self
               )
    end
  end
end
