defmodule Palee.Identity.Domain.EmailChangePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.EmailChangePolicy

  @now ~U[2026-12-24 14:00:00Z]

  test "new_address normalises and refuses invalid or unchanged addresses" do
    assert {:ok, "jo@box.test"} = EmailChangePolicy.new_address("  Jo@Box.TEST ", "old@box.test")

    assert {:error, :email_unchanged} =
             EmailChangePolicy.new_address("OLD@box.test", "old@box.test")

    assert {:error, :invalid_email} = EmailChangePolicy.new_address("jo@box", "old@box.test")

    assert {:error, :invalid_email} =
             EmailChangePolicy.new_address("a b@box.test", "old@box.test")

    assert {:error, :invalid_email} = EmailChangePolicy.new_address(nil, "old@box.test")
  end

  test "a pending change lives 24 h and a lock 7 days" do
    pending = %{expires_at: EmailChangePolicy.pending_expires_at(@now)}
    refute EmailChangePolicy.expired?(pending, DateTime.add(@now, 86_399, :second))
    assert EmailChangePolicy.expired?(pending, DateTime.add(@now, 86_400, :second))

    until = EmailChangePolicy.lock_until(@now)
    assert EmailChangePolicy.locked?(until, DateTime.add(@now, 6 * 86_400, :second))
    refute EmailChangePolicy.locked?(until, DateTime.add(@now, 7 * 86_400, :second))
    refute EmailChangePolicy.locked?(nil, @now)
  end

  test "same_address? ignores case and spaces" do
    assert EmailChangePolicy.same_address?(" Jo@Box.test", "jo@box.test")
    refute EmailChangePolicy.same_address?("jo@box.test", nil)
  end
end
