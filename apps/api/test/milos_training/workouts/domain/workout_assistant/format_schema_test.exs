defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.FormatSchemaTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.{JsonSchema, TimerConfig}
  alias MilosTraining.Workouts.Domain.WorkoutAssistant.{FormatSchema, Tools}
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  # A minimal section that satisfies the schema of `format`, built only from
  # the schema itself.
  defp sample_section(format) do
    schema = FormatSchema.section_schema(format)
    timer_schema = schema["properties"]["timer"]

    timer =
      Map.new(timer_schema["required"], fn key ->
        {key, sample_value(timer_schema["properties"][key])}
      end)

    exercise =
      case format do
        "rest" -> []
        "complex_emom" -> [%{"name" => "Row", "interval_assignment" => 1}]
        "even_odd" -> [%{"name" => "Row", "interval_assignment" => 1}]
        _other -> [%{"name" => "Row"}]
      end

    %{"name" => "Block", "format" => format, "timer" => timer, "exercises" => exercise}
  end

  defp sample_value(%{"enum" => [first | _rest]}), do: first
  defp sample_value(%{"type" => "string"}), do: "HR below 120"
  # 60 keeps interval ≤ duration and min_reps < start_reps is fixed below.
  defp sample_value(%{"type" => _numeric}), do: 60

  test "every backend format has a schema, a description and its timer keys" do
    assert FormatSchema.formats() == Vocabulary.section_formats()

    for format <- FormatSchema.formats() do
      schema = FormatSchema.section_schema(format)
      assert schema["properties"]["format"] == %{"const" => format}
      assert is_binary(FormatSchema.description(format))

      timer_keys = Map.keys(schema["properties"]["timer"]["properties"])

      assert Enum.sort(timer_keys) ==
               format
               |> Vocabulary.allowed_timer_fields()
               |> Enum.map(&Atom.to_string/1)
               |> Enum.sort()
    end
  end

  test "a section valid against its schema has a timer the backend accepts" do
    for format <- FormatSchema.formats() do
      section = sample_section(format)

      section =
        if format == "ladder_descending",
          do: put_in(section, ["timer", "min_reps"], 10),
          else: section

      assert JsonSchema.validate(FormatSchema.section_schema(format), section) == [],
             "#{format} sample should satisfy its own schema"

      assert FormatSchema.rule_violations(section, "s") == [], "#{format} sample breaks a rule"

      assert {:ok, %{type: ^format}} =
               TimerConfig.normalize(Map.put(section["timer"], "type", format)),
             "#{format} schema and TimerConfig disagree"
    end
  end

  test "missing required timer keys fail the schema and TimerConfig alike" do
    for format <- FormatSchema.formats(), FormatSchema.required_timer_keys(format) != [] do
      section = sample_section(format) |> Map.delete("timer")
      refute JsonSchema.validate(FormatSchema.section_schema(format), section) == []
    end
  end

  test "exercise structure differs per format" do
    assert "interval_assignment" in FormatSchema.exercise_schema("complex_emom")["required"]

    assert FormatSchema.exercise_schema("even_odd")["properties"]["interval_assignment"]["enum"] ==
             [1, 2]

    for format <- ~w(ladder_ascending ladder_descending pyramid death_by) do
      assert %{"not" => %{}} = FormatSchema.exercise_schema(format)["properties"]["reps"]
    end

    assert %{"not" => %{}} =
             FormatSchema.exercise_schema("tabata")["properties"]["duration_seconds"]

    assert %{"not" => %{}} =
             FormatSchema.exercise_schema("emom")["properties"]["interval_assignment"]

    assert FormatSchema.section_schema("rest")["properties"]["exercises"]["maxItems"] == 0
  end

  test "scores are limited to what the format allows" do
    assert FormatSchema.section_schema("amrap")["properties"]["score"]["enum"] ==
             Vocabulary.allowed_score_types("amrap")

    section = sample_section("amrap") |> Map.put("score", "time")

    assert [%{"path" => "score"}] =
             JsonSchema.validate(FormatSchema.section_schema("amrap"), section)
  end

  test "the answer schema discriminates sections by format" do
    schema = FormatSchema.answer_schema(~w(emom tabata))

    answer = %{
      "workout" => %{},
      "sections" => [sample_section("emom"), sample_section("tabata")],
      "issues" => [],
      "missing_fields" => []
    }

    assert JsonSchema.validate(schema, answer) == []

    broken = put_in(answer, ["sections", Access.at(1), "timer"], %{"work_seconds" => 20})
    errors = JsonSchema.validate(schema, broken)

    assert Enum.map(errors, & &1["path"]) |> Enum.sort() == [
             "sections.1.timer.rest_seconds",
             "sections.1.timer.rounds"
           ]

    unknown = put_in(answer, ["sections", Access.at(0), "format"], "amrap")

    assert [%{"path" => "sections.0", "problem" => problem}] =
             JsonSchema.validate(schema, unknown)

    assert problem =~ "format must be one of"
  end

  test "cross-field rules" do
    emom = %{
      "format" => "emom",
      "timer" => %{"duration_seconds" => 60, "interval_seconds" => 120},
      "exercises" => []
    }

    assert [%{"path" => "s.timer.interval_seconds"}] = FormatSchema.rule_violations(emom, "s")

    ladder = %{
      "format" => "ladder_descending",
      "timer" => %{"start_reps" => 9, "step_reps" => 3, "min_reps" => 21}
    }

    assert [%{"path" => "s.timer.min_reps"}] = FormatSchema.rule_violations(ladder, "s")

    complex = %{
      "format" => "complex_emom",
      "timer" => %{"duration_seconds" => 120, "interval_seconds" => 60},
      "exercises" => [
        %{"interval_assignment" => 1},
        %{"interval_assignment" => 2},
        %{"interval_assignment" => 3}
      ]
    }

    assert [%{"path" => "s.exercises.2.interval_assignment"}] =
             FormatSchema.rule_violations(complex, "s")
  end

  test "get_section_schema tool returns the canonical definitions" do
    result =
      Tools.call("get_section_schema", %{"formats" => ["EMOM", "circuit", "zumba", "emom"]})

    assert [%{"format" => "emom"} = emom, %{"format" => "untimed", "requested_as" => "circuit"}] =
             result["formats"]

    assert emom["required_timer_keys"] == ["duration_seconds", "interval_seconds"]
    assert emom["section_schema"] == FormatSchema.section_schema("emom")
    assert emom["rules"] != []
    assert result["unknown_formats"] == ["zumba"]

    assert %{name: "get_section_schema"} = hd(Tools.declarations(["get_section_schema"]))
    assert Jason.encode!(result)
  end

  test "outline schema accepts a structure and rejects unknown formats" do
    outline = %{"sections" => [%{"name" => "WOD", "format" => "amrap", "evidence" => "AMRAP 12"}]}
    assert JsonSchema.validate(FormatSchema.outline_schema(), outline) == []

    outline = put_in(outline, ["sections", Access.at(0), "format"], "zumba")

    assert [%{"path" => "sections.0.format"}] =
             JsonSchema.validate(FormatSchema.outline_schema(), outline)
  end
end
