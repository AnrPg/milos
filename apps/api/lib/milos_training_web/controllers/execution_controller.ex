defmodule MilosTrainingWeb.ExecutionController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    CompleteWorkout,
    GetWorkoutExecution,
    GetWorkoutTimerSequence,
    GetWorkoutVault,
    IngestExecutionInteractions,
    ListWorkoutExecutions,
    StartWorkoutExecution,
    UpdateExecutionProgress
  }

  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Execution"])
  security([%{"bearerAuth" => []}])

  @kpi_counters_schema %Schema{
    type: :object,
    description:
      "Device-observed execution KPIs (skips, countdown_skips, countdown_segments, pauses, " <>
        "paused_ms, finish_wizard_opens, first_started_at_ms). Counters never decrease.",
    additionalProperties: %Schema{type: :integer, minimum: 0}
  }

  @duration_adjustments_schema %Schema{
    type: :object,
    description:
      "Mid-workout clock changes in seconds, by segment key (countdowns and capped count-ups only).",
    additionalProperties: %Schema{type: :integer, minimum: -3600, maximum: 3600}
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    description: "Execution ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @scale_param %Parameter{
    name: :scale,
    in: :query,
    description: "Scale slug",
    required: false,
    schema: %Schema{type: :string}
  }

  operation(:create,
    summary: "Start a workout execution",
    request_body:
      {"Start execution params", "application/json",
       %Schema{
         type: :object,
         required: [:master_workout_id, :source],
         properties: %{
           master_workout_id: %Schema{type: :string, format: :uuid},
           scale_level_slug: %Schema{type: :string, nullable: true},
           source: %Schema{
             type: :string,
             enum: ["class_booking", "assigned", "self_selected", "repeat"]
           },
           source_reference_id: %Schema{type: :string, format: :uuid, nullable: true},
           timezone: %Schema{type: :string, default: "UTC"}
         }
       }},
    responses: [
      created: {"Execution", "application/json", %Schema{type: :object}},
      forbidden: {"Finance entitlement denied", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <-
           StartWorkoutExecution.call(execution_context(conn), current_user, params) do
      conn
      |> put_status(:created)
      |> json(%{execution: execution})
    end
  end

  operation(:show,
    summary: "Get an execution by id",
    parameters: [@id_param],
    responses: [
      ok: {"Execution", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <- GetWorkoutExecution.call(conn.assigns.user_context, id, current_user) do
      json(conn, %{execution: execution})
    end
  end

  operation(:complete,
    summary: "Complete a workout execution",
    parameters: [@id_param],
    request_body:
      {"Complete execution params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           timezone: %Schema{type: :string, default: "UTC"},
           checked_exercise_ids: %Schema{
             type: :array,
             items: %Schema{type: :string}
           },
           section_scores: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               required: [:section_id, :value],
               properties: %{
                 section_id: %Schema{type: :string, format: :uuid},
                 score_type: %Schema{type: :string},
                 value: %Schema{
                   oneOf: [
                     %Schema{type: :string},
                     %Schema{type: :integer},
                     %Schema{type: :number}
                   ]
                 },
                 unit: %Schema{type: :string, nullable: true}
               }
             }
           },
           total_elapsed_ms: %Schema{type: :integer, minimum: 0},
           section_elapsed_ms: %Schema{
             type: :object,
             additionalProperties: %Schema{type: :integer, minimum: 0}
           },
           segment_cycle_counts: %Schema{
             type: :object,
             additionalProperties: %Schema{type: :integer, minimum: 0}
           },
           kpi_counters: @kpi_counters_schema,
           duration_adjustments: @duration_adjustments_schema
         }
       }},
    responses: [
      ok: {"Execution", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}},
      forbidden: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def complete(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <-
           CompleteWorkout.call(conn.assigns.user_context, id, current_user.id, params) do
      json(conn, %{execution: execution})
    end
  end

  operation(:update_progress,
    summary: "Persist execution progress",
    parameters: [@id_param],
    request_body:
      {"Execution progress params", "application/json",
       %Schema{
         type: :object,
         required: [
           :expected_version,
           :operation_id,
           :checked_exercise_ids,
           :current_segment_index,
           :status,
           :paused_elapsed_ms
         ],
         properties: %{
           expected_version: %Schema{type: :integer, minimum: 1},
           operation_id: %Schema{type: :string, format: :uuid},
           checked_exercise_ids: %Schema{
             type: :array,
             items: %Schema{type: :string}
           },
           section_scores: %Schema{
             type: :array,
             maxItems: 100,
             items: %Schema{
               type: :object,
               required: [:section_id, :value],
               properties: %{
                 section_id: %Schema{type: :string, format: :uuid},
                 value: %Schema{
                   oneOf: [%Schema{type: :string, maxLength: 100}, %Schema{type: :number}]
                 },
                 unit: %Schema{type: :string, maxLength: 32, nullable: true},
                 score_type: %Schema{type: :string, maxLength: 32, nullable: true},
                 source: %Schema{type: :string, maxLength: 16, nullable: true},
                 kind: %Schema{type: :string, maxLength: 16, nullable: true}
               }
             }
           },
           current_segment_index: %Schema{type: :integer, minimum: 0},
           status: %Schema{type: :string, enum: ["active", "paused"]},
           segment_started_at_utc: %Schema{
             type: :string,
             format: :"date-time",
             nullable: true
           },
           paused_elapsed_ms: %Schema{type: :integer, minimum: 0},
           total_elapsed_ms: %Schema{type: :integer, minimum: 0},
           section_elapsed_ms: %Schema{
             type: :object,
             additionalProperties: %Schema{type: :integer, minimum: 0}
           },
           segment_cycle_counts: %Schema{
             type: :object,
             additionalProperties: %Schema{type: :integer, minimum: 0}
           },
           resume_countdown_ends_at_utc: %Schema{
             type: :string,
             format: :"date-time",
             nullable: true
           },
           kpi_counters: @kpi_counters_schema,
           duration_adjustments: @duration_adjustments_schema
         }
       }},
    responses: [
      ok: {"Execution", "application/json", %Schema{type: :object}},
      forbidden: {"Error", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}},
      conflict: {"Stale execution version", "application/json", %Schema{type: :object}}
    ]
  )

  def update_progress(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <-
           UpdateExecutionProgress.call(conn.assigns.user_context, id, current_user.id, params) do
      json(conn, %{execution: execution})
    end
  end

  operation(:timer_sequence,
    summary: "Get timer sequence for a workout",
    parameters: [
      @id_param,
      @scale_param,
      %Parameter{
        name: :source,
        in: :query,
        required: true,
        schema: %Schema{
          type: :string,
          enum: ["class_booking", "assigned", "self_selected", "repeat"]
        }
      },
      %Parameter{
        name: :source_reference_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Timer sequence", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def timer_sequence(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, segments} <-
           GetWorkoutTimerSequence.call(execution_context(conn), current_user, id, params) do
      json(conn, %{segments: segments})
    end
  end

  defp execution_context(conn) do
    Map.merge(
      conn.assigns.user_context,
      Map.take(conn.assigns[:tenant_context] || %{}, [:organization_id])
    )
  end

  operation(:index,
    summary: "List my workout executions",
    responses: [ok: {"Executions", "application/json", %Schema{type: :object}}]
  )

  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, executions} <-
           ListWorkoutExecutions.call(conn.assigns.user_context, current_user.id) do
      json(conn, %{executions: executions})
    end
  end

  @vault_entry_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      started_at_utc: %Schema{type: :string, format: :"date-time"},
      completed_at_utc: %Schema{type: :string, format: :"date-time"},
      completed_at_tz: %Schema{type: :string, nullable: true},
      scale_level_slug: %Schema{type: :string, nullable: true},
      source: %Schema{type: :string},
      total_elapsed_ms: %Schema{type: :integer}
    },
    required: [:id, :completed_at_utc, :source]
  }

  operation(:vault,
    summary: "My completed workouts, each with its dated entries (ADR-098)",
    responses: [
      ok:
        {"Workout vault", "application/json",
         %Schema{
           type: :object,
           properties: %{
             workouts: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   master_workout_id: %Schema{type: :string, format: :uuid},
                   workout_title: %Schema{type: :string, nullable: true},
                   workout_type: %Schema{type: :string, nullable: true},
                   completed_count: %Schema{type: :integer},
                   last_completed_at: %Schema{type: :string, format: :"date-time"},
                   entries: %Schema{type: :array, items: @vault_entry_schema}
                 },
                 required: [:master_workout_id, :completed_count, :last_completed_at, :entries]
               }
             }
           },
           required: [:workouts]
         }}
    ]
  )

  def vault(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, workouts} <- GetWorkoutVault.call(conn.assigns.user_context, current_user.id) do
      json(conn, %{workouts: workouts})
    end
  end

  # ADR-123: client-only execution interaction signals. The kind enum is the
  # Analytics allowlist itself, so the contract and validation cannot drift.
  @interaction_metadata_schema %Schema{
    type: :object,
    additionalProperties: false,
    description:
      "Typed facts allowed for the interaction kind (see ADR-123). No free text; " <>
        "keys not allowed for the kind reject the batch.",
    properties: %{
      segment_index: %Schema{type: :integer, minimum: 0, maximum: 10_000},
      section_id: %Schema{type: :string, pattern: "^[A-Za-z0-9_-]{1,64}$"},
      format: %Schema{type: :string, pattern: "^[A-Za-z0-9_-]{1,64}$"},
      surface: %Schema{
        type: :string,
        enum: [
          "pause_sheet",
          "primary_action",
          "header",
          "gesture",
          "keyboard",
          "snackbar",
          "ready_screen",
          "finish_wizard",
          "cast_display",
          "lock_screen"
        ]
      },
      round_count: %Schema{type: :integer, minimum: 0, maximum: 10_000},
      delta_rounds: %Schema{type: :integer, minimum: -100, maximum: 100},
      delta_seconds: %Schema{type: :integer, minimum: -3600, maximum: 3600},
      elapsed_ms: %Schema{type: :integer, minimum: 0, maximum: 86_400_000},
      remaining_ms: %Schema{type: :integer, minimum: 0, maximum: 86_400_000},
      duration_ms: %Schema{type: :integer, minimum: 0, maximum: 86_400_000},
      countdown_seconds: %Schema{type: :integer, minimum: 0, maximum: 600},
      step: %Schema{type: :integer, minimum: 0, maximum: 20},
      scored_section_count: %Schema{type: :integer, minimum: 0, maximum: 1000},
      enabled: %Schema{type: :boolean},
      orientation: %Schema{type: :string, enum: ["portrait", "landscape"]},
      cue_channel: %Schema{type: :string, enum: ["sound", "voice", "vibration"]}
    }
  }

  def interaction_metadata_schema, do: @interaction_metadata_schema

  operation(:record_interactions,
    summary: "Report client-only execution interaction events (analytics, ADR-123)",
    description:
      "Batched, idempotent ingestion of execution interaction signals the server cannot " <>
        "observe (pause sheet, manual skip, round taps, adjusts, ready screen, finish " <>
        "wizard, cast mode). Each event dedupes on its client_event_id; retries are " <>
        "accepted and counted as duplicates. Any invalid event rejects the batch.",
    parameters: [@id_param],
    request_body:
      {"Interaction events", "application/json",
       %Schema{
         title: "ExecutionInteractionBatch",
         type: :object,
         required: [:events],
         properties: %{
           events: %Schema{
             type: :array,
             minItems: 1,
             maxItems: MilosTraining.Analytics.execution_interaction_max_batch(),
             items: %Schema{
               title: "ExecutionInteractionEvent",
               type: :object,
               required: [:client_event_id, :kind, :occurred_at],
               properties: %{
                 client_event_id: %Schema{type: :string, format: :uuid},
                 kind: %Schema{
                   type: :string,
                   enum: MilosTraining.Analytics.execution_interaction_kinds()
                 },
                 occurred_at: %Schema{type: :string, format: :"date-time"},
                 metadata: @interaction_metadata_schema
               }
             }
           }
         }
       }},
    responses: [
      accepted:
        {"Batch accepted", "application/json",
         %Schema{
           title: "ExecutionInteractionBatchResult",
           type: :object,
           required: [:accepted, :duplicates],
           properties: %{
             accepted: %Schema{type: :integer, minimum: 0},
             duplicates: %Schema{type: :integer, minimum: 0}
           }
         }},
      not_found: {"Execution not found", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"Invalid interaction batch", "application/json",
         %Schema{
           type: :object,
           required: [:code, :errors],
           properties: %{
             code: %Schema{type: :string, enum: ["invalid_execution_interactions"]},
             errors: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 required: [:index, :reason],
                 properties: %{
                   index: %Schema{type: :integer},
                   reason: %Schema{type: :string}
                 }
               }
             }
           }
         }}
    ]
  )

  def record_interactions(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    case IngestExecutionInteractions.call(
           conn.assigns[:user_context],
           id,
           current_user.id,
           Map.get(params, "events")
         ) do
      {:ok, result} ->
        conn
        |> put_status(:accepted)
        |> json(result)

      {:error, {:invalid_execution_interactions, errors}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{code: "invalid_execution_interactions", errors: errors})

      {:error, reason} ->
        {:error, reason}
    end
  end
end
