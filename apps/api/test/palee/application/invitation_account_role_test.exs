defmodule Palee.Application.InvitationAccountRoleTest do
  use ExUnit.Case, async: true

  alias Palee.Application.InvitationAccountRole

  test "staff invitations open the staff shell, athletes stay athletes, the rest are members" do
    for role <- [:owner, :admin, :coach, :front_desk, :accountant, :janitor] do
      assert InvitationAccountRole.for_invitation(role) == :admin
    end

    assert InvitationAccountRole.for_invitation(:athlete) == :athlete
    assert InvitationAccountRole.for_invitation(:member) == :member
  end

  test "an existing profile is only ever lifted" do
    assert InvitationAccountRole.promotes?(:member, :admin)
    assert InvitationAccountRole.promotes?(:athlete, :admin)
    assert InvitationAccountRole.promotes?(:member, :athlete)
    refute InvitationAccountRole.promotes?(:admin, :admin)
    refute InvitationAccountRole.promotes?(:admin, :member)
    refute InvitationAccountRole.promotes?(:athlete, :member)
  end
end
