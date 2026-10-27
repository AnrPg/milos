defmodule PaleeWeb.EmailChangeControllerTest do
  @moduledoc "ADR-207: the email change endpoints."
  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  import Palee.TestFixtures

  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}

  @password "S3cur3P@ss!42"

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    %{user: user_fixture()}
  end

  defp json_conn(conn),
    do: put_req_header(conn, "content-type", "application/json")

  defp token_for(email) do
    message = assert_email_enqueued(kind: :email_change_confirm, to: email)
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]+)/, message.text)
    token
  end

  defp start_change(conn, user, email) do
    conn
    |> put_bearer_token(user)
    |> post("/api/me/email-change", Jason.encode!(%{email: email, current_password: @password}))
  end

  test "GET shows nothing pending at first", %{conn: conn, user: user} do
    assert %{"pending" => nil, "locked_until" => nil} =
             conn |> put_bearer_token(user) |> get("/api/me/email-change") |> json_response(200)
  end

  test "POST with a wrong password is refused", %{conn: conn, user: user} do
    body =
      conn
      |> put_bearer_token(user)
      |> post(
        "/api/me/email-change",
        Jason.encode!(%{email: "new@box.test", current_password: "nope"})
      )
      |> json_response(422)

    assert body["code"] == "invalid_current_password"
    refute_email_enqueued(kind: :email_change_confirm)
  end

  test "POST answers the same for a free and a taken address", %{conn: conn, user: user} do
    other = user_fixture()

    free = conn |> start_change(user, "free@box.test") |> json_response(202)
    assert free["pending"]["email"] == "free@box.test"

    taken = build_conn() |> start_change(user, other.email) |> json_response(202)
    assert Map.keys(taken) == Map.keys(free)
    assert taken["pending"]["email"] == other.email
  end

  test "POST refuses an invalid or unchanged address", %{conn: conn, user: user} do
    assert %{"code" => "invalid_email"} =
             conn |> start_change(user, "nope") |> json_response(422)

    assert %{"code" => "email_unchanged"} =
             build_conn() |> start_change(user, user.email) |> json_response(422)
  end

  test "resend is throttled right after the request; cancel drops it", %{conn: conn, user: user} do
    conn |> start_change(user, "new@box.test") |> json_response(202)

    assert build_conn()
           |> put_bearer_token(user)
           |> post("/api/me/email-change/resend")
           |> json_response(429)

    assert %{"pending" => nil} =
             build_conn()
             |> put_bearer_token(user)
             |> delete("/api/me/email-change")
             |> json_response(200)

    assert %{"code" => "no_pending_email_change"} =
             build_conn()
             |> put_bearer_token(user)
             |> post("/api/me/email-change/resend")
             |> json_response(404)
  end

  test "PATCH /api/me/profile no longer changes the email", %{conn: conn, user: user} do
    body =
      conn
      |> put_bearer_token(user)
      |> patch(
        "/api/me/profile",
        Jason.encode!(%{email: "new@box.test", current_password: @password})
      )
      |> json_response(422)

    assert body["code"] == "email_change_needs_confirmation"
    assert Identity.find_by_id(user.id).email == user.email

    # The unchanged address may still come along with a profile edit.
    assert build_conn()
           |> put_bearer_token(user)
           |> patch(
             "/api/me/profile",
             Jason.encode!(%{email: user.email, preferred_locale: "el"})
           )
           |> json_response(200)
  end

  describe "POST /api/auth/email-change/confirm" do
    test "from a signed-out browser: changes the email, no session", %{conn: conn, user: user} do
      conn |> start_change(user, "new@box.test") |> json_response(202)
      token = token_for("new@box.test")

      body =
        build_conn()
        |> json_conn()
        |> post("/api/auth/email-change/confirm", Jason.encode!(%{token: token}))
        |> json_response(200)

      assert body == %{"email" => "new@box.test", "access_token" => nil}
      assert Identity.find_by_id(user.id).email == "new@box.test"

      # The old access token died with the security version.
      assert build_conn() |> put_bearer_token(user) |> get("/api/auth/me") |> response(401)
    end

    test "the signed-in browser of the same login gets a fresh session", %{user: user} do
      login =
        build_conn()
        |> json_conn()
        |> post("/api/auth/login", Jason.encode!(%{identifier: user.email, password: @password}))

      refresh = login.resp_cookies["palee_refresh"].value
      start_change(build_conn(), user, "new@box.test") |> json_response(202)
      token = token_for("new@box.test")

      confirmed =
        build_conn()
        |> json_conn()
        |> put_req_cookie("palee_refresh", refresh)
        |> post("/api/auth/email-change/confirm", Jason.encode!(%{token: token}))

      body = json_response(confirmed, 200)
      assert is_binary(body["access_token"])
      assert body["user"]["email"] == "new@box.test"
      assert confirmed.resp_cookies["palee_refresh"].value != refresh

      assert build_conn()
             |> put_req_header("authorization", "Bearer " <> body["access_token"])
             |> get("/api/auth/me")
             |> json_response(200)
             |> Map.fetch!("email") == "new@box.test"
    end

    test "invalid, expired and conflicting links", %{conn: conn, user: user} do
      assert %{"code" => "invalid_email_change_link"} =
               conn
               |> json_conn()
               |> post("/api/auth/email-change/confirm", Jason.encode!(%{token: "junk"}))
               |> json_response(422)

      {:ok, expired, _} =
        LinkTokens.issue(:email_change, user.login_id,
          target_email: "x@box.test",
          now: DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)
        )

      assert %{"code" => "expired_email_change_link"} =
               build_conn()
               |> json_conn()
               |> post("/api/auth/email-change/confirm", Jason.encode!(%{token: expired}))
               |> json_response(410)

      start_change(build_conn(), user, "taken@box.test") |> json_response(202)
      token = token_for("taken@box.test")
      user_fixture(%{email: "taken@box.test"})

      assert %{"code" => "email_change_unavailable"} =
               build_conn()
               |> json_conn()
               |> post("/api/auth/email-change/confirm", Jason.encode!(%{token: token}))
               |> json_response(409)
    end
  end

  describe "POST /api/auth/email-change/revert" do
    test "restores the old address and locks new changes", %{conn: conn, user: user} do
      conn |> start_change(user, "new@box.test") |> json_response(202)

      build_conn()
      |> json_conn()
      |> post(
        "/api/auth/email-change/confirm",
        Jason.encode!(%{token: token_for("new@box.test")})
      )
      |> json_response(200)

      {:ok, raw, _} =
        LinkTokens.issue(:email_change_revert, user.login_id, target_email: user.email)

      assert %{"email" => email} =
               build_conn()
               |> json_conn()
               |> post("/api/auth/email-change/revert", Jason.encode!(%{token: raw}))
               |> json_response(200)

      assert email == user.email
      account = Identity.find_by_id(user.id)
      assert account.email == user.email

      body = build_conn() |> start_change(account, "again@box.test") |> json_response(409)
      assert body["code"] == "email_change_locked"
      assert is_binary(body["locked_until"])

      assert %{"code" => "invalid_email_change_link"} =
               build_conn()
               |> json_conn()
               |> post("/api/auth/email-change/revert", Jason.encode!(%{token: raw}))
               |> json_response(422)
    end
  end
end
