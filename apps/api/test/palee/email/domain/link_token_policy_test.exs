defmodule Palee.Email.Domain.LinkTokenPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.LinkTokenPolicy

  @now ~U[2026-12-24 12:00:00.000000Z]

  test "tokens are 32 random url-safe bytes, hashed with SHA-256" do
    raw = LinkTokenPolicy.generate()
    assert byte_size(raw) == 43
    assert raw =~ ~r/\A[A-Za-z0-9_-]+\z/
    assert LinkTokenPolicy.well_formed?(raw)
    refute raw == LinkTokenPolicy.generate()
    assert LinkTokenPolicy.hash(raw) == :crypto.hash(:sha256, raw)
    refute LinkTokenPolicy.well_formed?("short")
    refute LinkTokenPolicy.well_formed?(nil)
  end

  test "every purpose has a lifetime" do
    assert LinkTokenPolicy.purposes() ==
             ~w(account_deletion email_change email_change_revert password_reset sign_out_everywhere verify_email)

    assert LinkTokenPolicy.ttl_seconds("password_reset") == 3_600
    assert LinkTokenPolicy.ttl_seconds("verify_email") == 48 * 3_600
    refute LinkTokenPolicy.replaces_previous?("email_change_revert")
    # ADR-208: every security notice keeps its own sign-out link working.
    refute LinkTokenPolicy.replaces_previous?("sign_out_everywhere")
    assert LinkTokenPolicy.replaces_previous?("password_reset")
    assert {:ok, "verify_email"} = LinkTokenPolicy.purpose(:verify_email)
    assert :error = LinkTokenPolicy.purpose("unknown")
  end

  test "expiry and use" do
    expires_at = LinkTokenPolicy.expires_at("password_reset", @now)
    assert expires_at == ~U[2026-12-24 13:00:00.000000Z]
    token = %{expires_at: expires_at, used_at: nil}

    assert LinkTokenPolicy.usable?(token, @now)
    assert :ok = LinkTokenPolicy.check(token, @now)
    assert LinkTokenPolicy.expired?(token, expires_at)
    assert {:error, :expired} = LinkTokenPolicy.check(token, DateTime.add(expires_at, 1))
    assert {:error, :used} = LinkTokenPolicy.check(%{token | used_at: @now}, @now)
    refute LinkTokenPolicy.usable?(%{token | used_at: @now}, @now)
  end
end
