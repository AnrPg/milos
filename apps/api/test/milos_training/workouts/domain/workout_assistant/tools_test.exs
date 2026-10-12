defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.ToolsTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutAssistant.Tools

  test "lookup_exercises finds exact, alias and close matches" do
    %{"results" => [exact, alias_match, close, none]} =
      Tools.call("lookup_exercises", %{"names" => ["Back Squat", "OHS", "back sqaut", "zzzz"]})

    assert exact["match"] == "canonical"
    assert exact["exercise"]["id"] == "back-squat"
    assert alias_match["exercise"]["id"] == "overhead-squat"
    assert close["match"] == "close"
    assert hd(close["candidates"])["id"] == "back-squat"
    assert none["match"] == "none"
  end

  test "get_timer_format describes canonical keys and resolves aliases" do
    emom = Tools.call("get_timer_format", %{"format" => "emom"})
    assert emom["required_keys"] == ["duration_seconds", "interval_seconds"]
    assert Tools.call("get_timer_format", %{"format" => "circuit"})["format"] == "untimed"
    assert Tools.call("get_timer_format", %{"format" => "nope"})["error"] == "unknown_format"
  end

  test "convert_units converts common gym units" do
    assert Tools.call("convert_units", %{"value" => 225, "from" => "lb", "to" => "kg"}) == %{
             "value" => 102.06
           }

    assert Tools.call("convert_units", %{"value" => "3", "from" => "min", "to" => "s"}) == %{
             "value" => 180.0
           }

    assert Tools.call("convert_units", %{"value" => 1, "from" => "kg", "to" => "min"})["error"]
  end

  test "validate_draft runs the contract against the source" do
    result =
      Tools.call("validate_draft", %{"draft_json" => ~s({"workout":{},"sections":[]})}, %{
        source: "x"
      })

    refute result["valid"]
    assert Enum.any?(result["violations"], &(&1["path"] == "issues"))
  end

  test "declarations are valid Gemini function declarations" do
    for declaration <- Tools.declarations(Tools.names()) do
      assert is_binary(declaration.name)
      assert declaration.parameters.type == "OBJECT"
      assert declaration.parameters.required != []
    end
  end

  test "unknown tools answer with an error instead of raising" do
    assert Tools.call("drop_tables", %{}) == %{"error" => "unknown_tool", "tool" => "drop_tables"}
  end
end
