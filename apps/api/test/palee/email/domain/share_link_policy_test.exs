defmodule Palee.Email.Domain.ShareLinkPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.ShareLinkPolicy

  @now ~U[2026-12-24 12:00:00Z]

  test "kinds are read from the request, nothing else" do
    assert ShareLinkPolicy.kind("guest_pass") == {:ok, :guest_pass}
    assert ShareLinkPolicy.kind(:referral) == {:ok, :referral}
    assert ShareLinkPolicy.kind("owner_invitation") == :error
    assert ShareLinkPolicy.kind(nil) == :error
  end

  test "ten a rolling day per sender" do
    recent = for minutes <- 1..9, do: %{inserted_at: DateTime.add(@now, -minutes * 60)}
    old = %{inserted_at: DateTime.add(@now, -25 * 3600)}

    assert ShareLinkPolicy.within_limit?([old | recent], @now)
    refute ShareLinkPolicy.within_limit?([%{inserted_at: @now} | recent], @now)
  end

  test "one key per sender, link and recipient, under the sender's prefix" do
    key = ShareLinkPolicy.key("sender", :referral, "ABC", "a@b.test")

    assert String.starts_with?(key, ShareLinkPolicy.sender_prefix("sender"))
    assert key == ShareLinkPolicy.key("sender", :referral, "ABC", "a@b.test")
    refute key == ShareLinkPolicy.key("sender", :referral, "ABC", "c@d.test")
    refute key == ShareLinkPolicy.key("sender", :guest_pass, "ABC", "a@b.test")
    refute key =~ "a@b.test"
  end

  test "a name that reads as a link or an address shows the handle instead" do
    assert ShareLinkPolicy.sender_name("Μαρία Π.", "maria") == "Μαρία Π."
    assert ShareLinkPolicy.sender_name("win at spam.example", "spammer") == "@spammer"
    assert ShareLinkPolicy.sender_name("https://x", "spammer") == "@spammer"
    assert ShareLinkPolicy.sender_name("me@mail.test", "spammer") == "@spammer"
    assert ShareLinkPolicy.sender_name("  Jo\u0000\nDoe ", "jo") == "Jo Doe"
    assert String.length(ShareLinkPolicy.sender_name(String.duplicate("a", 200), "a")) == 60
  end
end
