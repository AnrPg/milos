defmodule PaleeWeb.EmailVerificationControllerTest do
  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  alias Palee.Identity
  alias Palee.Infrastructure.Auth.Guardian
  alias Palee.Infrastructure.Security.MemoryRateLimiter

  setup do
    MemoryRateLimiter.reset!()
    :ok
  end

  defp sign_up!(conn) do
    unique = System.unique_integer([:positive])
    email = "verify_web_#{unique}@example.com"

    body =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/auth/register",
        Jason.encode!(%{
          handle: "verify_web_#{unique}",
          password: "a b c d",
          role: "member",
          email: email,
          age_confirmed: true
        })
      )
      |> json_response(201)

    user = Identity.find_by_handle("verify_web_#{unique}")
    {user, body["access_token"]}
  end

  defp token_of(user) do
    message = assert_email_enqueued(kind: :verify_email, login_id: user.login_id)
    [_, token] = Regex.run(~r{/verify-email#token=([A-Za-z0-9_-]+)}, message.text)
    token
  end

  defp post_token(conn, token) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/verify-email", Jason.encode!(%{token: token}))
  end

  test "sign-up emails a link; posting its token verifies, once", %{conn: conn} do
    {user, access_token} = sign_up!(conn)
    token = token_of(user)

    me = fn ->
      build_conn()
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> get("/api/auth/me")
      |> json_response(200)
    end

    assert %{"email_verified" => false} = me.()
    assert %{"email_verified" => true} = build_conn() |> post_token(token) |> json_response(200)
    assert %{"email_verified" => true} = me.()

    assert %{"code" => "used_verification_link"} =
             build_conn() |> post_token(token) |> json_response(409)
  end

  test "an unknown link is 422 and a missing token is a validation error", %{conn: conn} do
    assert %{"code" => "invalid_verification_link"} =
             conn |> post_token(String.duplicate("a", 43)) |> json_response(422)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("/api/auth/verify-email", "{}")
           |> json_response(422)
  end

  test "a link to an address the login no longer has is refused clearly", %{conn: conn} do
    {user, _access_token} = sign_up!(conn)
    token = token_of(user)
    {:ok, _user} = Identity.update_credentials(user.id, %{email: "changed@example.com"})

    assert %{"code" => "verification_email_changed"} =
             build_conn() |> post_token(token) |> json_response(409)
  end

  describe "POST /api/auth/verification-email" do
    test "needs a signed-in person", %{conn: conn} do
      assert conn |> post("/api/auth/verification-email") |> json_response(401)
    end

    test "is throttled right after sign-up, with a retry-after", %{conn: conn} do
      {_user, access_token} = sign_up!(conn)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> post("/api/auth/verification-email")

      assert %{"code" => "throttled", "retry_after_seconds" => seconds} =
               json_response(conn, 429)

      assert seconds in 1..60
      assert get_resp_header(conn, "retry-after") == [Integer.to_string(seconds)]
    end

    test "answers already_verified for a verified login", %{conn: conn} do
      {user, _access_token} = sign_up!(conn)
      :ok = Identity.mark_email_verified(user.login_id, user.email)

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => user.security_version}, token_type: "access")

      assert %{"status" => "already_verified"} =
               build_conn()
               |> put_req_header("authorization", "Bearer " <> access_token)
               |> post("/api/auth/verification-email")
               |> json_response(200)
    end
  end
end
