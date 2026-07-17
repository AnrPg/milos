defmodule MilosTraining.Organizations.Domain.InvitationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.InvitationPolicy

  @now ~U[2026-07-18 10:00:00.000000Z]

  test "accepts only bounded invitation lifetimes" do
    assert InvitationPolicy.valid_lifetime?(300)
    assert InvitationPolicy.valid_lifetime?(604_800)
    refute InvitationPolicy.valid_lifetime?(299)
    refute InvitationPolicy.valid_lifetime?(604_801)
  end

  test "derives active and expired state from an explicit clock" do
    assert InvitationPolicy.state(%{expires_at: ~U[2026-07-18 10:00:01.000000Z]}, @now) ==
             :active

    assert InvitationPolicy.state(%{expires_at: @now}, @now) == :expired
  end

  test "terminal state takes precedence over expiration" do
    expired_at = ~U[2026-07-18 09:00:00.000000Z]

    assert InvitationPolicy.state(%{expires_at: expired_at, redeemed_at: @now}, @now) ==
             :redeemed

    assert InvitationPolicy.state(%{expires_at: expired_at, revoked_at: @now}, @now) ==
             :revoked
  end

  test "only active invitations are redeemable" do
    assert InvitationPolicy.redeemable?(
             %{expires_at: ~U[2026-07-18 10:00:01.000000Z]},
             @now
           )

    refute InvitationPolicy.redeemable?(%{expires_at: @now}, @now)
    refute InvitationPolicy.redeemable?(%{expires_at: @now, revoked_at: @now}, @now)
  end
end
