defmodule MilosTrainingWeb.Schemas.WorkoutDsl do
  @moduledoc false

  alias OpenApiSpex.Schema

  def parse_request_schema do
    %Schema{
      title: "WorkoutDslParseRequest",
      type: :object,
      properties: %{
        source: %Schema{type: :string, minLength: 1, maxLength: 200_000}
      },
      required: [:source],
      additionalProperties: false
    }
  end

  def diagnostic_schema do
    %Schema{
      title: "WorkoutDslDiagnostic",
      type: :object,
      properties: %{
        code: %Schema{type: :string},
        line: %Schema{type: :integer, minimum: 1},
        column: %Schema{type: :integer, minimum: 1},
        params: %Schema{type: :object, additionalProperties: true}
      },
      required: [:code, :line, :column, :params],
      additionalProperties: false
    }
  end

  def parse_response_schema do
    %Schema{
      title: "WorkoutDslParseResponse",
      type: :object,
      properties: %{
        version: %Schema{type: :integer, enum: [1]},
        workout: %Schema{type: :object, additionalProperties: true},
        formatted_source: %Schema{type: :string},
        vocabulary: vocabulary_schema()
      },
      required: [:version, :workout, :formatted_source, :vocabulary],
      additionalProperties: false
    }
  end

  def diagnostic_response_schema do
    %Schema{
      title: "WorkoutDslDiagnosticResponse",
      type: :object,
      properties: %{
        diagnostics: %Schema{type: :array, items: diagnostic_schema()}
      },
      required: [:diagnostics],
      additionalProperties: false
    }
  end

  def vocabulary_schema do
    %Schema{
      title: "WorkoutDslVocabulary",
      type: :object,
      properties: %{
        version: %Schema{type: :integer, enum: [1]},
        section_formats: string_array(),
        workout_parameters: string_array(),
        exercise_parameters: string_array(),
        header_parameters: string_array(),
        note_markers: string_array(),
        section_parameters: %Schema{
          type: :object,
          additionalProperties: string_array()
        }
      },
      required: [
        :version,
        :section_formats,
        :workout_parameters,
        :exercise_parameters,
        :header_parameters,
        :note_markers,
        :section_parameters
      ],
      additionalProperties: false
    }
  end

  defp string_array, do: %Schema{type: :array, items: %Schema{type: :string}}
end
