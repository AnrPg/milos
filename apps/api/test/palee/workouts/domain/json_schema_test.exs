defmodule Palee.Workouts.Domain.JsonSchemaTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.JsonSchema

  defp errors(schema, data),
    do: schema |> JsonSchema.validate(data) |> Enum.map(&{&1["path"], &1["problem"]})

  test "types, ranges and lengths" do
    assert errors(%{"type" => "integer", "minimum" => 1}, 0) == [{"", "must be ≥ 1"}]
    assert errors(%{"type" => "integer"}, 2.0) == []
    assert errors(%{"type" => "integer"}, 2.5) == [{"", "must be integer"}]
    assert errors(%{"type" => "number", "exclusiveMinimum" => 0}, 0) == [{"", "must be > 0"}]
    assert errors(%{"type" => ["string", "null"]}, nil) == []

    assert errors(%{"type" => "string", "maxLength" => 2}, "abc") == [
             {"", "must have at most 2 characters"}
           ]

    assert errors(%{"enum" => [1, 2]}, 3) == [{"", "must be one of 1, 2"}]
    assert errors(%{"const" => "emom"}, "amrap") == [{"", "must be \"emom\""}]
  end

  test "objects and arrays report nested paths" do
    schema = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["a"],
      "properties" => %{
        "a" => %{"type" => "array", "maxItems" => 1, "items" => %{"type" => "integer"}}
      }
    }

    assert errors(schema, %{"b" => 1}) == [{"a", "is required"}, {"b", "is not allowed here"}]

    assert errors(schema, %{"a" => [1, "x"]}) == [
             {"a", "must have at most 1 items"},
             {"a.1", "must be integer"}
           ]
  end

  test "not reports its description and $ref resolves into $defs" do
    schema = %{
      "$defs" => %{"slot" => %{"not" => %{}, "description" => "must be omitted for emom"}},
      "type" => "object",
      "properties" => %{"slot" => %{"$ref" => "#/$defs/slot"}}
    }

    assert errors(schema, %{"slot" => 1}) == [{"slot", "must be omitted for emom"}]
    assert errors(schema, %{}) == []
  end
end
