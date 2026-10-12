defmodule MilosTrainingWeb.ClassTimerController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{CommandClassTimer, GetClassTimer}
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Class Timers"])
  security([%{"bearerAuth" => []}])

  @slot_param %Parameter{
    name: :slot_id,
    in: :path,
    description: "Scheduled class ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @timer_schema %Schema{
    type: :object,
    properties: %{
      status: %Schema{type: :string, enum: ~w(ready running paused finished)},
      current_segment_index: %Schema{type: :integer, minimum: 0},
      segment_started_at_utc: %Schema{type: :string, format: :"date-time", nullable: true},
      paused_elapsed_ms: %Schema{type: :integer, minimum: 0},
      duration_adjustments: %Schema{type: :object, additionalProperties: true},
      timer_preset: %Schema{type: :object, nullable: true, additionalProperties: true},
      lock_version: %Schema{type: :integer},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:status, :current_segment_index, :paused_elapsed_ms, :lock_version]
  }

  @payload_schema %Schema{
    type: :object,
    properties: %{
      class: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          name: %Schema{type: :string},
          scheduled_at: %Schema{type: :string, format: :"date-time"},
          duration_minutes: %Schema{type: :integer}
        }
      },
      workout: %Schema{type: :object, nullable: true, additionalProperties: true},
      segments: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
      timer: @timer_schema,
      server_now: %Schema{type: :string, format: :"date-time"}
    },
    required: [:class, :segments, :timer, :server_now]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  operation(:show,
    summary: "Read the coach-run timer of a scheduled class",
    parameters: [@slot_param],
    responses: [
      ok: {"Class timer", "application/json", @payload_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def show(conn, %{"slot_id" => slot_id}) do
    with {:ok, payload} <- GetClassTimer.call(conn.assigns.tenant_context, slot_id) do
      json(conn, payload)
    end
  end

  operation(:command,
    summary: "Run a class timer command (coaches and admins)",
    parameters: [@slot_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              command: %Schema{
                type: :string,
                enum: ~w(start pause resume next previous jump adjust reset finish configure)
              },
              expected_version: %Schema{type: :integer, minimum: 1, nullable: true},
              index: %Schema{type: :integer, minimum: 0},
              delta_seconds: %Schema{type: :integer, minimum: -3600, maximum: 3600},
              countdown_seconds: %Schema{type: :integer, minimum: 0, maximum: 60},
              timer_preset: %Schema{type: :object, additionalProperties: true}
            },
            required: [:command]
          }
        }
      }
    },
    responses: [
      ok: {"Class timer", "application/json", @payload_schema},
      forbidden: {"Forbidden", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      conflict: {"Stale class timer version", "application/json", @error_schema},
      unprocessable_entity: {"Invalid command", "application/json", @error_schema}
    ]
  )

  def command(conn, %{"slot_id" => slot_id}) do
    actor = Guardian.Plug.current_resource(conn)

    case CommandClassTimer.call(conn.assigns.tenant_context, actor, slot_id, conn.body_params) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :stale_class_timer} ->
        conn
        |> put_status(:conflict)
        |> json(%{code: "stale_class_timer", error: "The class timer changed on another device"})

      {:error, reason}
      when reason in [:invalid_command, :invalid_transition, :no_segments, :class_timer_running] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{code: to_string(reason), error: "The class timer cannot do that right now"})

      other ->
        other
    end
  end
end
