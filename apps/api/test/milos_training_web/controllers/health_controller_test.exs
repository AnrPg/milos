defmodule MilosTrainingWeb.HealthControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  setup do
    original_readiness_checker = Application.get_env(:milos_training, :readiness_checker)
    original_force_ssl = Application.get_env(:milos_training, :force_ssl)

    on_exit(fn ->
      Application.put_env(:milos_training, :readiness_checker, original_readiness_checker)
      Application.put_env(:milos_training, :force_ssl, original_force_ssl)
    end)

    :ok
  end

  test "returns 200 when dependencies are ready", %{conn: conn} do
    Application.put_env(
      :milos_training,
      :readiness_checker,
      MilosTraining.TestSupport.FakeReadinessOk
    )

    conn = get(conn, "/api/health")

    body = json_response(conn, 200)
    assert body["status"] == "ok"
    assert body["dependencies"] == %{"database" => "ok", "redis" => "ok"}
  end

  test "returns 503 when a dependency is unavailable", %{conn: conn} do
    Application.put_env(
      :milos_training,
      :readiness_checker,
      MilosTraining.TestSupport.FakeReadinessError
    )

    conn = get(conn, "/api/health")

    body = json_response(conn, 503)
    assert body["status"] == "error"
    assert body["dependencies"] == %{"database" => "ok", "redis" => "error"}
  end

  test "does not redirect health checks when SSL enforcement is enabled", %{conn: conn} do
    Application.put_env(
      :milos_training,
      :readiness_checker,
      MilosTraining.TestSupport.FakeReadinessOk
    )

    Application.put_env(:milos_training, :force_ssl, hsts: true, rewrite_on: [:x_forwarded_proto])

    conn = get(conn, "/api/health")

    assert json_response(conn, 200)["status"] == "ok"
  end

  test "does not redirect health checks arriving as IPv4-mapped IPv6 (Bandit dual-stack)", %{
    conn: conn
  } do
    Application.put_env(
      :milos_training,
      :readiness_checker,
      MilosTraining.TestSupport.FakeReadinessOk
    )

    Application.put_env(:milos_training, :force_ssl, hsts: true, rewrite_on: [:x_forwarded_proto])

    # ::ffff:10.244.0.1 — how Bandit reports an IPv4 kubelet probe on an IPv6 socket
    conn =
      conn
      |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0xFFFF, 0x0AF4, 0x0001})
      |> get("/api/health")

    assert json_response(conn, 200)["status"] == "ok"
  end

  test "still redirects external health requests when SSL enforcement is enabled", %{conn: conn} do
    Application.put_env(:milos_training, :force_ssl, hsts: true, rewrite_on: [:x_forwarded_proto])

    conn =
      conn
      |> Map.put(:remote_ip, {8, 8, 8, 8})
      |> get("/api/health")

    assert response(conn, 301)
    assert [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, "https://")
    assert String.ends_with?(location, "/api/health")
  end

  test "still redirects non-health HTTP requests when SSL enforcement is enabled", %{conn: conn} do
    Application.put_env(:milos_training, :force_ssl, hsts: true, rewrite_on: [:x_forwarded_proto])

    conn = get(conn, "/api/openapi")

    assert response(conn, 301)
    assert [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, "https://")
    assert String.ends_with?(location, "/api/openapi")
  end
end
