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
        severity: %Schema{type: :string, enum: ["error", "warning"]},
        line: %Schema{type: :integer, minimum: 1},
        column: %Schema{type: :integer, minimum: 1},
        params: %Schema{type: :object, additionalProperties: true}
      },
      required: [:code, :severity, :line, :column, :params],
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
        vocabulary: vocabulary_schema(),
        diagnostics: %Schema{type: :array, items: diagnostic_schema()}
      },
      required: [:version, :workout, :formatted_source, :vocabulary, :diagnostics],
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

  def publish_request_schema do
    %Schema{
      title: "WorkoutDslPublishRequest",
      type: :object,
      properties: %{
        source: %Schema{type: :string, minLength: 1, maxLength: 200_000},
        document: %Schema{type: :object, additionalProperties: true, nullable: true},
        expected_source_revision: %Schema{type: :integer, minimum: 0},
        acknowledge_warnings: %Schema{type: :boolean, default: false}
      },
      required: [:source, :expected_source_revision],
      additionalProperties: false
    }
  end

  def publish_response_schema do
    %Schema{
      title: "WorkoutDslPublishResponse",
      type: :object,
      properties: %{
        workout: %Schema{type: :object, additionalProperties: true},
        formatted_source: %Schema{type: :string},
        diagnostics: %Schema{type: :array, items: diagnostic_schema()},
        execution_preview: %Schema{type: :object, additionalProperties: true}
      },
      required: [:workout, :formatted_source, :diagnostics, :execution_preview],
      additionalProperties: false
    }
  end

  def authoring_response_schema do
    %Schema{
      title: "WorkoutDslAuthoringResponse",
      type: :object,
      properties: %{
        version: %Schema{type: :integer, enum: [1]},
        source: %Schema{type: :string},
        document: %Schema{type: :object, additionalProperties: true, nullable: true},
        source_revision: %Schema{type: :integer, minimum: 0},
        authoring_mode: %Schema{type: :string, enum: ["structured", "quick_text"]},
        diagnostics: %Schema{type: :array, items: diagnostic_schema()}
      },
      required: [
        :version,
        :source,
        :source_revision,
        :authoring_mode,
        :diagnostics
      ],
      additionalProperties: false
    }
  end

  def manual_response_schema do
    %Schema{
      title: "WorkoutDslManualResponse",
      type: :object,
      properties: %{
        version: %Schema{type: :integer, enum: [1]},
        markdown: %Schema{type: :string},
        templates: %Schema{type: :object, additionalProperties: true},
        vocabulary: vocabulary_schema()
      },
      required: [:version, :markdown, :templates, :vocabulary],
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
        format_aliases: %Schema{type: :object, additionalProperties: true},
        format_specs: %Schema{type: :object, additionalProperties: true},
        workout_parameters: string_array(),
        exercise_parameters: string_array(),
        group_parameters: string_array(),
        scale_parameters: string_array(),
        header_parameters: string_array(),
        note_markers: string_array(),
        exercise_catalog: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string},
              label: %Schema{type: :string},
              category: %Schema{type: :string},
              aliases: string_array(),
              capabilities: string_array()
            },
            required: [:id, :label, :category, :aliases, :capabilities],
            additionalProperties: false
          }
        },
        section_parameters: %Schema{
          type: :object,
          additionalProperties: string_array()
        }
      },
      required: [
        :version,
        :section_formats,
        :format_aliases,
        :format_specs,
        :workout_parameters,
        :exercise_parameters,
        :group_parameters,
        :scale_parameters,
        :header_parameters,
        :note_markers,
        :section_parameters,
        :exercise_catalog
      ],
      additionalProperties: false
    }
  end

  defp string_array, do: %Schema{type: :array, items: %Schema{type: :string}}
end
