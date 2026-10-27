defmodule Palee.Email.Domain.UnsubscribeTokenTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.{KeyExpiry, RetentionPolicy, UnsubscribeToken}

  @key :crypto.strong_rand_bytes(32)
  @claims %{
    digest: :crypto.hash(:sha256, "jo@box.test"),
    kind: "corporate_invoice_issued",
    locale: "pt_PT"
  }

  test "a signed token verifies with its key and carries no readable address" do
    token = UnsubscribeToken.sign(@key, @claims)

    assert {:ok, @claims} = UnsubscribeToken.verify(@key, token)
    assert token =~ ~r/\A[A-Za-z0-9_-]+\z/
    refute token =~ "jo"
  end

  test "a token signed with another key, or changed, is refused" do
    token = UnsubscribeToken.sign(@key, @claims)

    assert :error = UnsubscribeToken.verify(:crypto.strong_rand_bytes(32), token)

    {:ok, raw} = Base.url_decode64(token, padding: false)
    <<first, rest::binary>> = raw
    tampered = Base.url_encode64(<<Bitwise.bxor(first, 1), rest::binary>>, padding: false)
    assert :error = UnsubscribeToken.verify(@key, tampered)

    for bad <- ["", "!!", String.duplicate("A", 500), nil, 42],
        do: assert(:error = UnsubscribeToken.verify(@key, bad))
  end

  test "key expiry states" do
    expires = ~D[2027-10-26]

    assert KeyExpiry.state(nil, ~D[2027-01-01]) == :unknown
    assert KeyExpiry.state(expires, ~D[2027-09-25]) == :ok
    assert KeyExpiry.state(expires, ~D[2027-09-26]) == {:expiring, 30}
    assert KeyExpiry.state(expires, ~D[2027-10-26]) == {:expiring, 0}
    assert KeyExpiry.state(expires, ~D[2027-10-27]) == :expired
    assert KeyExpiry.parse(" 2027-10-26 ") == expires
    assert KeyExpiry.parse("26/10/2027") == nil
  end

  test "retention cut-offs" do
    now = ~U[2027-01-31 12:00:00Z]

    assert RetentionPolicy.messages_before(now) == ~U[2026-11-02 12:00:00Z]
    assert RetentionPolicy.link_tokens_before(now) == ~U[2027-01-24 12:00:00Z]
    assert RetentionPolicy.pending_statuses() == ~w(queued deferred)
  end
end
