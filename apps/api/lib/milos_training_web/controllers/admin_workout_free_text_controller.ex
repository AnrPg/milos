defmodule MilosTrainingWeb.AdminWorkoutFreeTextController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.AnalyzeFreeTextWorkout
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @nullable_string %Schema{type: :string, nullable: true}

  @suggestion_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      label: @nullable_string,
      value: %Schema{nullable: true, description: "Canonical value for the issue path"},
      text_edit: %Schema{
        type: :object,
        nullable: true,
        properties: %{find: %Schema{type: :string}, replace: %Schema{type: :string}},
        required: [:find, :replace]
      }
    }
  }

  @issue_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string},
      path: %Schema{
        type: :string,
        description: "Canonical field path, or \"text\" for a text-only correction"
      },
      code: %Schema{
        type: :string,
        description:
          "assistant | text_correction | assumption (severity info: a value the assistant inferred; Keep or Reject) | missing_title | missing_type | missing_section_name | missing_exercise_name | too_short | invalid_value | invalid_timer | unknown_format"
      },
      severity: %Schema{type: :string, enum: ["error", "warning", "info"]},
      kind: %Schema{
        type: :string,
        nullable: true,
        description:
          "For text_correction: spelling | unit | number | abbreviation | format | ambiguity"
      },
      required: %Schema{type: :boolean},
      message: @nullable_string,
      params: %Schema{type: :object, additionalProperties: true},
      current_value: %Schema{nullable: true},
      suggestion: @suggestion_schema
    },
    required: [:id, :path, :code, :severity, :required, :params]
  }

  @missing_field_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string},
      path: %Schema{type: :string},
      field: %Schema{type: :string},
      reason: @nullable_string,
      value: %Schema{nullable: true},
      text_insert: @nullable_string
    },
    required: [:id, :path, :field]
  }

  @response_schema %Schema{
    title: "FreeTextWorkoutAnalysis",
    type: :object,
    properties: %{
      workout: %Schema{
        type: :object,
        additionalProperties: true,
        description:
          "Canonical workout: title, type, subtitle, description, difficulty, estimated_duration_seconds, equipment, tags and sections[] with name, note, timer_config (its own format per section), scoreable/score_config and exercises[] (interval_assignment for complex_emom / even_odd)"
      },
      issues: %Schema{type: :array, items: @issue_schema},
      suggestions: %Schema{type: :array, items: @missing_field_schema},
      quality: %Schema{
        type: :object,
        description: "How much the parser answer had to be repaired against the contract",
        properties: %{
          repair_attempts: %Schema{type: :integer},
          remaining_violations: %Schema{type: :integer},
          corrections: %Schema{type: :integer},
          structure_inferred: %Schema{
            type: :boolean,
            description:
              "Whether the structure step (sections and their formats) succeeded before parsing"
          }
        }
      },
      summary: %Schema{
        type: :object,
        properties: %{
          sections: %Schema{type: :integer},
          exercises: %Schema{type: :integer},
          errors: %Schema{type: :integer},
          warnings: %Schema{type: :integer},
          blocking: %Schema{type: :integer}
        },
        required: [:sections, :exercises, :errors, :warnings, :blocking]
      }
    },
    required: [:workout, :issues, :suggestions, :summary]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  operation(:analyze,
    summary: "Read a free-text workout into the canonical schema with actionable issues",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              text: %Schema{type: :string, maxLength: 20_000},
              locale: %Schema{type: :string, maxLength: 10}
            },
            required: [:text]
          }
        }
      }
    },
    responses: [
      ok: {"Analysis", "application/json", @response_schema},
      unprocessable_entity: {"Invalid text", "application/json", @error_schema},
      bad_gateway: {"Assistant unavailable", "application/json", @error_schema},
      service_unavailable: {"Assistant not configured", "application/json", @error_schema}
    ]
  )

  def analyze(conn, _params) do
    case AnalyzeFreeTextWorkout.call(conn.assigns.tenant_context, conn.body_params) do
      {:ok, analysis} -> json(conn, analysis)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, reason) do
    {status, code, message} =
      case reason do
        :text_required ->
          {:unprocessable_entity, "text_required", "Write the workout before analyzing it"}

        :text_too_long ->
          {:unprocessable_entity, "text_too_long", "The workout text is too long to analyze"}

        :analyzer_not_configured ->
          {:service_unavailable, "analyzer_not_configured", "The workout assistant is not set up"}

        :analyzer_invalid_response ->
          {:bad_gateway, "analyzer_invalid_response", "The workout assistant answered unclearly"}

        _other ->
          {:bad_gateway, "analyzer_unavailable", "The workout assistant is unavailable"}
      end

    conn
    |> put_status(status)
    |> json(%{code: code, error: message})
  end
end
