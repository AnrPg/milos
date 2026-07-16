defmodule MilosTrainingWeb.AuthControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Auth.Guardian
  alias MilosTraining.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    :ok
  end

  describe "POST /api/auth/register" do
    test "returns tokens on valid registration", %{conn: conn} do
      params = %{nickname: "zeus", password: "S3cur3P@ss!", role: "member"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", Jason.encode!(params))

      assert %{"access_token" => _} = json_response(conn, 201)
      refute Map.has_key?(json_response(conn, 201), "refresh_token")
      assert conn.resp_cookies["milos_refresh"].http_only
      assert conn.resp_cookies["milos_refresh"].same_site == "Strict"
    end

    test "returns 422 on duplicate nickname", %{conn: conn} do
      params = %{nickname: "zeus", password: "S3cur3P@ss!", role: "member"}

      _ =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", Jason.encode!(params))

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", Jason.encode!(params))

      assert json_response(conn, 422)["errors"]["nickname"] != []
    end

    test "returns 500 when token issuance fails", %{conn: conn} do
      original = Application.get_env(:milos_training, :token_issuer)

      Application.put_env(
        :milos_training,
        :token_issuer,
        MilosTraining.TestSupport.FailingTokenIssuer
      )

      on_exit(fn ->
        Application.put_env(:milos_training, :token_issuer, original)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/register",
          Jason.encode!(%{nickname: "hephaestus", password: "S3cur3P@ss!", role: "member"})
        )

      assert %{"error" => "Authentication service unavailable"} = json_response(conn, 500)
      assert Identity.find_by_nickname("hephaestus") == nil
    end
  end

  describe "POST /api/auth/login" do
    setup do
      {:ok, _user} =
        Identity.register(%{
          nickname: "hermes",
          password: "S3cur3P@ss!",
          role: :member
        })

      :ok
    end

    test "returns tokens on valid credentials", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(%{nickname: "hermes", password: "S3cur3P@ss!"}))

      assert json_response(conn, 200)["access_token"]
      refute Map.has_key?(json_response(conn, 200), "refresh_token")
      assert conn.resp_cookies["milos_refresh"].http_only
    end

    test "returns 401 on wrong password", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/login",
          Jason.encode!(%{nickname: "hermes", password: "wrong-password"})
        )

      assert %{"error" => "Invalid credentials"} = json_response(conn, 401)
    end

    test "returns 429 after exceeding the auth rate limit", %{conn: conn} do
      params = %{nickname: "missing-user", password: "wrong-password"}

      Enum.each(1..10, fn _ ->
        conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))
      end)

      blocked_conn =
        conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))

      assert %{"error" => "Too many requests"} = json_response(blocked_conn, 429)
    end

    test "rate limits by forwarded client IP rather than shared proxy IP", %{conn: conn} do
      params = %{nickname: "missing-user", password: "wrong-password"}

      Enum.each(1..10, fn _ ->
        conn
        |> recycle()
        |> Map.put(:remote_ip, {172, 18, 0, 5})
        |> put_req_header("x-forwarded-for", "203.0.113.10")
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))
      end)

      other_client_conn =
        conn
        |> recycle()
        |> Map.put(:remote_ip, {172, 18, 0, 5})
        |> put_req_header("x-forwarded-for", "203.0.113.11")
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))

      assert %{"error" => "Invalid credentials"} = json_response(other_client_conn, 401)
    end

    test "ignores spoofed leftmost forwarded IPs and keys rate limiting to the nearest client IP",
         %{conn: conn} do
      params = %{nickname: "missing-user", password: "wrong-password"}

      Enum.each(1..10, fn index ->
        conn
        |> recycle()
        |> Map.put(:remote_ip, {172, 18, 0, 5})
        |> put_req_header("x-forwarded-for", "198.51.100.#{index}, 203.0.113.10")
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))
      end)

      blocked_conn =
        conn
        |> recycle()
        |> Map.put(:remote_ip, {172, 18, 0, 5})
        |> put_req_header("x-forwarded-for", "192.0.2.44, 203.0.113.10")
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(params))

      assert %{"error" => "Too many requests"} = json_response(blocked_conn, 429)
    end

    test "returns 503 when the rate limiter backend is unavailable", %{conn: conn} do
      original = Application.get_env(:milos_training, :rate_limiter)

      Application.put_env(
        :milos_training,
        :rate_limiter,
        MilosTraining.TestSupport.FailingRateLimiter
      )

      on_exit(fn ->
        Application.put_env(:milos_training, :rate_limiter, original)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/login",
          Jason.encode!(%{nickname: "missing-user", password: "wrong-password"})
        )

      assert %{"error" => "Rate limiter unavailable"} = json_response(conn, 503)
    end

    test "returns 500 when token issuance fails after valid credentials", %{conn: conn} do
      original = Application.get_env(:milos_training, :token_issuer)

      Application.put_env(
        :milos_training,
        :token_issuer,
        MilosTraining.TestSupport.FailingTokenIssuer
      )

      on_exit(fn ->
        Application.put_env(:milos_training, :token_issuer, original)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/login", Jason.encode!(%{nickname: "hermes", password: "S3cur3P@ss!"}))

      assert %{"error" => "Authentication service unavailable"} = json_response(conn, 500)
    end
  end

  describe "POST /api/auth/refresh" do
    test "returns no content when no refresh cookie is present", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh", %{})

      assert response(conn, 204) == ""
    end

    test "rotates refresh tokens and rejects replay of the old token", %{conn: conn} do
      register_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/register",
          Jason.encode!(%{nickname: "apollo", password: "S3cur3P@ss!", role: "member"})
        )

      refresh_token = register_conn.resp_cookies["milos_refresh"].value

      refresh_conn =
        build_conn()
        |> put_req_cookie("milos_refresh", refresh_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh", %{})

      assert %{"access_token" => _} = json_response(refresh_conn, 200)
      rotated_refresh_token = refresh_conn.resp_cookies["milos_refresh"].value

      refute rotated_refresh_token == refresh_token

      replay_conn =
        build_conn()
        |> put_req_cookie("milos_refresh", refresh_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh", %{})

      assert %{"error" => "Invalid refresh token"} = json_response(replay_conn, 401)
    end

    test "returns 503 and leaves the original refresh token usable when token store revoke fails",
         %{conn: conn} do
      register_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/register",
          Jason.encode!(%{nickname: "odin", password: "S3cur3P@ss!", role: "member"})
        )

      refresh_token = register_conn.resp_cookies["milos_refresh"].value

      original = Application.get_env(:milos_training, :token_store)

      Application.put_env(
        :milos_training,
        :token_store,
        MilosTraining.TestSupport.FailingTokenStore
      )

      on_exit(fn ->
        Application.put_env(:milos_training, :token_store, original)
      end)

      failing_refresh_conn =
        build_conn()
        |> put_req_cookie("milos_refresh", refresh_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh", %{})

      assert %{"error" => "Authentication dependency unavailable"} =
               json_response(failing_refresh_conn, 503)

      Application.put_env(:milos_training, :token_store, original)

      retry_refresh_conn =
        build_conn()
        |> put_req_cookie("milos_refresh", refresh_token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh", %{})

      assert %{"access_token" => _} = json_response(retry_refresh_conn, 200)
      assert retry_refresh_conn.resp_cookies["milos_refresh"].value != refresh_token
    end
  end

  describe "session-family revocation" do
    test "sign out all invalidates existing access and refresh credentials", %{conn: conn} do
      login_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/auth/register",
          Jason.encode!(%{nickname: "security_family", password: "S3cur3P@ss!", role: "member"})
        )

      %{"access_token" => access_token} = json_response(login_conn, 201)
      refresh_token = login_conn.resp_cookies["milos_refresh"].value

      login_conn
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> post("/api/auth/sign-out-all", %{})
      |> response(204)

      build_conn()
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> get("/api/auth/me")
      |> json_response(401)

      build_conn()
      |> put_req_cookie("milos_refresh", refresh_token)
      |> post("/api/auth/refresh", %{})
      |> json_response(401)
    end
  end

  describe "GET /api/auth/me" do
    test "returns 401 without a bearer token", %{conn: conn} do
      conn = get(conn, "/api/auth/me")
      assert %{"error" => "Unauthorized"} = json_response(conn, 401)
    end

    test "returns the authenticated user", %{conn: conn} do
      {:ok, user} =
        Identity.register(%{
          nickname: "ares",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, access_token, _claims} = Guardian.encode_and_sign(user, %{}, token_type: "access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> get("/api/auth/me")

      body = json_response(conn, 200)
      assert body["id"] == user.id
      assert body["nickname"] == "ares"
      assert body["role"] == "member"
      assert body["preferred_locale"] == "en"
    end
  end

  describe "PATCH /api/admin/users/:id/role" do
    test "allows admins to update a user's role", %{conn: conn} do
      {:ok, admin} =
        Identity.register(%{
          nickname: "hera",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, admin} = Identity.update_role(admin, :admin)

      {:ok, athlete} =
        Identity.register(%{
          nickname: "poseidon",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(admin, %{"sv" => admin.security_version}, token_type: "access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/admin/users/#{athlete.id}/role", Jason.encode!(%{role: "athlete"}))

      body = json_response(conn, 200)
      assert body["id"] == athlete.id
      assert body["nickname"] == "poseidon"
      assert body["role"] == "athlete"
    end

    test "returns 403 for non-admins", %{conn: conn} do
      {:ok, member} =
        Identity.register(%{
          nickname: "demeter",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, athlete} =
        Identity.register(%{
          nickname: "artemis",
          password: "S3cur3P@ss!",
          role: :athlete
        })

      {:ok, access_token, _claims} = Guardian.encode_and_sign(member, %{}, token_type: "access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/admin/users/#{athlete.id}/role", Jason.encode!(%{role: "member"}))

      assert %{"error" => "Forbidden"} = json_response(conn, 403)
    end

    test "returns 404 for a missing user instead of crashing", %{conn: conn} do
      {:ok, admin} =
        Identity.register(%{
          nickname: "athena",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, admin} = Identity.update_role(admin, :admin)

      {:ok, access_token, _claims} =
        Guardian.encode_and_sign(admin, %{"sv" => admin.security_version}, token_type: "access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> access_token)
        |> put_req_header("content-type", "application/json")
        |> patch(
          "/api/admin/users/#{Ecto.UUID.generate()}/role",
          Jason.encode!(%{role: "member"})
        )

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end
  end
end
