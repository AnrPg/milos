defmodule PaleeWeb.AuthErrorHandlerTest do
  use PaleeWeb.ConnCase, async: true

  alias Palee.TestSupport.TelemetryCapture
  alias PaleeWeb.AuthErrorHandler

  setup do
    TelemetryCapture.capture([[:palee, :auth, :anomaly]])
  end

  test "rejects with 401 and records the Guardian failure type", %{conn: conn} do
    response =
      conn
      |> AuthErrorHandler.auth_error({:invalid_token, :token_expired}, [])
      |> json_response(401)

    assert response == %{"code" => "unauthorized", "error" => "Unauthorized"}

    assert_received {:telemetry_event, [:palee, :auth, :anomaly], %{count: 1},
                     %{reason: "invalid_token"}}
  end

  test "maps unexpected Guardian failure types to a bounded label", %{conn: conn} do
    conn
    |> AuthErrorHandler.auth_error({{:weird, "x"}, :nope}, [])
    |> json_response(401)

    assert_received {:telemetry_event, [:palee, :auth, :anomaly], %{count: 1},
                     %{reason: "guardian_other"}}
  end
end
