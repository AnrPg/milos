defmodule MilosTrainingWeb.HealthControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:milos_training, :readiness_checker)

    on_exit(fn ->
      Application.put_env(:milos_training, :readiness_checker, original)
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
end
