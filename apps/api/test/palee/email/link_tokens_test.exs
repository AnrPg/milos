defmodule Palee.Email.LinkTokensTest do
  use Palee.DataCase, async: true

  import Palee.TestFixtures

  alias Palee.Email.LinkTokens

  setup do
    %{user: user_fixture()}
  end

  test "a link is consumed once", %{user: user} do
    assert {:ok, raw, token} =
             LinkTokens.issue("verify_email", user.login_id,
               user_id: user.id,
               target_email: "jo@box.test",
               metadata: %{"from" => "signup"}
             )

    refute token.token_hash == raw
    assert {:ok, peeked} = LinkTokens.peek(:verify_email, raw)
    assert peeked.id == token.id
    assert {:ok, used} = LinkTokens.consume("verify_email", raw)
    assert used.used_at
    assert used.metadata == %{"from" => "signup"}
    assert {:error, :used} = LinkTokens.consume("verify_email", raw)
    assert {:error, :used} = LinkTokens.peek("verify_email", raw)
  end

  test "wrong purpose, junk and unknown tokens are invalid", %{user: user} do
    {:ok, raw, _token} = LinkTokens.issue(:password_reset, user.login_id)

    assert {:error, :invalid} = LinkTokens.consume("verify_email", raw)
    assert {:error, :invalid} = LinkTokens.consume("password_reset", "junk")
    assert {:error, :invalid} = LinkTokens.consume("nope", raw)

    assert {:error, :invalid} =
             LinkTokens.consume("password_reset", Palee.Email.Domain.LinkTokenPolicy.generate())

    assert_raise ArgumentError, fn -> LinkTokens.issue("nope", user.login_id) end
  end

  test "an expired link is refused", %{user: user} do
    past = DateTime.add(DateTime.utc_now(), -7_200, :second)
    {:ok, raw, _token} = LinkTokens.issue("password_reset", user.login_id, now: past)

    assert {:error, :expired} = LinkTokens.peek("password_reset", raw)
    assert {:error, :expired} = LinkTokens.consume("password_reset", raw)
  end

  test "a new link replaces older unused ones, except email change reverts", %{user: user} do
    {:ok, first, _} = LinkTokens.issue("password_reset", user.login_id)
    {:ok, second, _} = LinkTokens.issue("password_reset", user.login_id)
    assert {:error, :invalid} = LinkTokens.peek("password_reset", first)
    assert {:ok, _} = LinkTokens.peek("password_reset", second)

    {:ok, revert_one, _} = LinkTokens.issue("email_change_revert", user.login_id)
    {:ok, revert_two, _} = LinkTokens.issue("email_change_revert", user.login_id)
    assert {:ok, _} = LinkTokens.consume("email_change_revert", revert_one)
    assert {:ok, _} = LinkTokens.consume("email_change_revert", revert_two)
  end

  test "of two racing consumers exactly one wins", %{user: user} do
    {:ok, raw, _token} = LinkTokens.issue("sign_out_everywhere", user.login_id)
    parent = self()

    results =
      1..4
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Palee.Repo, parent, self())
          LinkTokens.consume("sign_out_everywhere", raw)
        end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :used})) == 3
  end
end
