defmodule MilosTrainingWeb.ErrorJSONTest do
  use MilosTrainingWeb.ConnCase, async: true

  test "renders 404" do
    assert MilosTrainingWeb.ErrorJSON.render("404.json", %{}) == %{
             code: "not_found",
             error: "Not Found"
           }
  end

  test "renders 500" do
    assert MilosTrainingWeb.ErrorJSON.render("500.json", %{}) == %{
             code: "unexpected_server_error",
             error: "Internal Server Error"
           }
  end
end
