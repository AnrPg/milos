defmodule MilosTraining.Organizations.InvitationTokenTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.InvitationToken

  test "generates URL-safe opaque tokens and deterministic SHA-256 digests" do
    token = InvitationToken.generate()

    assert byte_size(token) >= 43
    assert token =~ ~r/^[A-Za-z0-9_-]+$/
    assert byte_size(InvitationToken.digest(token)) == 32
    assert InvitationToken.digest(token) == InvitationToken.digest(token)
  end

  test "rejects missing and oversized tokens before hashing" do
    assert {:error, :invalid_invitation} = InvitationToken.decode(nil)
    assert {:error, :invalid_invitation} = InvitationToken.decode(String.duplicate("a", 257))
  end
end
