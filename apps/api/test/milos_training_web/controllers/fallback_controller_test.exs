defmodule MilosTrainingWeb.FallbackControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

  alias MilosTraining.TestSupport.TelemetryCapture
  alias MilosTrainingWeb.FallbackController

  test "returns a stable semantic code while retaining compatibility prose", %{conn: conn} do
    response =
      conn
      |> FallbackController.call({:error, :not_found})
      |> json_response(404)

    assert response == %{"code" => "not_found", "error" => "Not found"}
  end

  test "returns interpolation parameters separately from compatibility prose", %{conn: conn} do
    response =
      conn
      |> FallbackController.call({:error, {:class_type_replacement_required, 3}})
      |> json_response(409)

    assert response["code"] == "class_type_replacement_required"
    assert response["error"] == "Future classes require a replacement class type"
    assert response["params"] == %{"future_class_count" => 3}
  end

  test "uses the semantic validation envelope for field errors", %{conn: conn} do
    response =
      conn
      |> FallbackController.call({:error, [nickname: "is required"]})
      |> json_response(422)

    assert response == %{
             "code" => "validation_failed",
             "errors" => %{"nickname" => ["is required"]}
           }
  end

  test "returns a client-correctable code for invalid assignment recipients", %{conn: conn} do
    response =
      conn
      |> FallbackController.call({:error, :invalid_athletes})
      |> json_response(422)

    assert response["code"] == "invalid_athletes"
  end

  test "includes the exact missing package benefit in entitlement denials", %{conn: conn} do
    response =
      conn
      |> FallbackController.call(
        {:error, :finance_capability_not_included, %{capability: :execute_assigned_workouts}}
      )
      |> json_response(403)

    assert response["code"] == "finance_capability_not_included"
    assert response["params"] == %{"capability" => "execute_assigned_workouts"}
  end

  describe "auth anomaly telemetry" do
    setup do
      TelemetryCapture.capture([[:milos, :auth, :anomaly]])
    end

    for reason <- [:invalid_credentials, :invalid_refresh_token, :invalid_token] do
      test "emits an auth anomaly for #{reason}", %{conn: conn} do
        conn |> FallbackController.call({:error, unquote(reason)}) |> json_response(401)

        expected_reason = Atom.to_string(unquote(reason))

        assert_received {:telemetry_event, [:milos, :auth, :anomaly], %{count: 1},
                         %{reason: ^expected_reason}}
      end
    end

    test "does not emit auth anomalies for unrelated failures", %{conn: conn} do
      conn |> FallbackController.call({:error, :not_found}) |> json_response(404)

      refute_received {:telemetry_event, [:milos, :auth, :anomaly], _measurements, _metadata}
    end
  end
end
