defmodule MilosTrainingWeb.ExecutionController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    AddExecutionModifications,
    CompleteWorkout,
    GetWorkoutExecution,
    GetWorkoutTimerSequence,
    ListWorkoutExecutions,
    StartWorkoutExecution,
    SubmitExecutionNote,
    UpdateExecutionProgress
  }

  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Execution"])
  security([%{"bearerAuth" => []}])

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
             enum: ["class_booking", "assigned", "self_selected"]
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

    with {:ok, execution} <- StartWorkoutExecution.call(current_user, params) do
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

    with {:ok, execution} <- GetWorkoutExecution.call(id, current_user) do
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
           }
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

    with {:ok, execution} <- CompleteWorkout.call(id, current_user.id, params) do
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
           }
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

    with {:ok, execution} <- UpdateExecutionProgress.call(id, current_user.id, params) do
      json(conn, %{execution: execution})
    end
  end

  operation(:submit_note,
    summary: "Submit an execution note and notify admins",
    parameters: [@id_param],
    request_body:
      {"Execution note params", "application/json",
       %Schema{
         type: :object,
         required: [:exercise_id, :selected_text, :selection_start, :selection_end],
         properties: %{
           id: %Schema{type: :string, format: :uuid, nullable: true},
           exercise_id: %Schema{type: :string},
           selected_text: %Schema{type: :string},
           selection_start: %Schema{type: :integer, minimum: 0},
           selection_end: %Schema{type: :integer, minimum: 1},
           tags: %Schema{type: :array, items: %Schema{type: :string}},
           note_text: %Schema{type: :string, nullable: true}
         }
       }},
    responses: [
      ok: {"Execution", "application/json", %Schema{type: :object}},
      forbidden: {"Error", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def submit_note(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <- SubmitExecutionNote.call(id, current_user.id, params) do
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
          enum: ["class_booking", "assigned", "self_selected"]
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

    with {:ok, segments} <- GetWorkoutTimerSequence.call(current_user, id, params) do
      json(conn, %{segments: segments})
    end
  end

  operation(:index,
    summary: "List my workout executions",
    responses: [ok: {"Executions", "application/json", %Schema{type: :object}}]
  )

  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, executions} <- ListWorkoutExecutions.call(current_user.id) do
      json(conn, %{executions: executions})
    end
  end

  operation(:add_modifications,
    summary: "Log exercise modifications during execution",
    parameters: [@id_param],
    request_body:
      {"Modifications", "application/json",
       %Schema{
         type: :object,
         required: [:modifications],
         properties: %{
           modifications: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               required: [:exercise_id, :type],
               properties: %{
                 exercise_id: %Schema{type: :string},
                 type: %Schema{
                   type: :string,
                   enum: ["skipped", "weight_changed", "reps_changed", "time_changed", "other"]
                 },
                 prescribed_value: %Schema{type: :number, nullable: true},
                 actual_value: %Schema{type: :number, nullable: true},
                 prescribed_mins: %Schema{type: :number, nullable: true},
                 actual_mins: %Schema{type: :number, nullable: true},
                 sets: %Schema{type: :integer, nullable: true},
                 note: %Schema{type: :string, nullable: true}
               }
             }
           }
         }
       }},
    responses: [
      ok: {"Execution", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def add_modifications(conn, %{"id" => id, "modifications" => modifications}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, execution} <- AddExecutionModifications.call(id, current_user.id, modifications) do
      json(conn, %{execution: execution})
    end
  end
end
