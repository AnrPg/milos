defmodule MilosTrainingWeb.FallbackControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

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
end
