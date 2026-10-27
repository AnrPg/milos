defmodule Palee.Identity.Domain.PasswordResetPolicyTest do
  @moduledoc "ADR-206: limits of the emailed reset link and of handler requests."
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.PasswordResetPolicy

  @now ~U[2026-12-24 12:00:00Z]

  defp ago(minutes), do: DateTime.add(@now, -minutes * 60, :second)

  test "one reset email every 10 minutes" do
    assert PasswordResetPolicy.email_allowed?([], @now)
    refute PasswordResetPolicy.email_allowed?([ago(9)], @now)
    assert PasswordResetPolicy.email_allowed?([ago(10)], @now)
  end

  test "five reset emails a rolling day" do
    four = Enum.map(1..4, &ago(&1 * 60))
    assert PasswordResetPolicy.email_allowed?(four, @now)
    refute PasswordResetPolicy.email_allowed?([ago(300) | four], @now)
    assert PasswordResetPolicy.email_allowed?([ago(24 * 60) | four], @now)
  end

  test "three handler requests a day per client" do
    assert PasswordResetPolicy.handler_request_allowed?(2)
    refute PasswordResetPolicy.handler_request_allowed?(3)
  end

  test "emailed links work an hour; handler links keep 24 hours" do
    assert PasswordResetPolicy.email_link_ttl_seconds() == 3600
    assert PasswordResetPolicy.link_expires_at(@now) == DateTime.add(@now, 24 * 3600, :second)
  end
end
