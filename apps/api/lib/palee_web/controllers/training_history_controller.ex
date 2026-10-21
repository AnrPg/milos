defmodule PaleeWeb.TrainingHistoryController do
  @moduledoc """
  Paged training log: workouts done with their performance, and booked
  classes with the class workout and the member's performance. Served for
  the signed-in user (`mine`) and for coaches/admins viewing a user's profile
  (`for_user`).
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.GetTrainingHistory
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  tags(["Training Log"])
  security([%{"bearerAuth" => []}])

  @nullable_string %Schema{type: :string, nullable: true}

  @workout_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      id: %Schema{type: :string},
      title: @nullable_string,
      type: @nullable_string,
      sections: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            name: @nullable_string,
            nested: %Schema{type: :boolean},
            format: %Schema{type: :string},
            timer_config: %Schema{type: :object, nullable: true, additionalProperties: true},
            score_type: @nullable_string,
            exercises: %Schema{
              type: :array,
              items: %Schema{type: :object, additionalProperties: true}
            }
          }
        }
      }
    }
  }

  @performance_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      execution_id: %Schema{type: :string},
      status: %Schema{type: :string},
      started_at: @nullable_string,
      completed_at: @nullable_string,
      elapsed_ms: %Schema{type: :integer, nullable: true},
      scale_level_slug: @nullable_string,
      scores: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            section_id: @nullable_string,
            section_name: @nullable_string,
            score_type: @nullable_string,
            value: %Schema{nullable: true},
            unit: @nullable_string
          }
        }
      }
    },
    required: [:execution_id, :status, :scores]
  }

  @response_schema %Schema{
    title: "TrainingHistoryPage",
    type: :object,
    properties: %{
      kind: %Schema{type: :string, enum: ["workouts", "classes"]},
      total: %Schema{type: :integer},
      offset: %Schema{type: :integer},
      next_offset: %Schema{type: :integer, nullable: true},
      entries: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            occurred_at: @nullable_string,
            source: @nullable_string,
            class: %Schema{
              type: :object,
              nullable: true,
              properties: %{
                name: @nullable_string,
                type_name: @nullable_string,
                duration_minutes: %Schema{type: :integer, nullable: true},
                attendance: @nullable_string
              }
            },
            workout: @workout_schema,
            performance: @performance_schema
          },
          required: [:id, :workout, :performance]
        }
      }
    },
    required: [:kind, :total, :offset, :next_offset, :entries]
  }

  @page_parameters [
    %Parameter{
      name: :kind,
      in: :query,
      schema: %Schema{type: :string, enum: ["workouts", "classes"], default: "workouts"}
    },
    %Parameter{name: :offset, in: :query, schema: %Schema{type: :integer, minimum: 0}},
    %Parameter{name: :limit, in: :query, schema: %Schema{type: :integer, minimum: 1, maximum: 50}}
  ]

  operation(:mine,
    summary: "The signed-in user's training log (workouts or booked classes) with performance",
    parameters: @page_parameters,
    responses: [ok: {"Training log page", "application/json", @response_schema}]
  )

  def mine(conn, params) do
    user = GuardianPlug.current_resource(conn)
    render_page(conn, user.id, params)
  end

  operation(:for_user,
    summary: "A user's training log (workouts or booked classes) with performance",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
      | @page_parameters
    ],
    responses: [ok: {"Training log page", "application/json", @response_schema}]
  )

  def for_user(conn, %{id: user_id} = params), do: render_page(conn, user_id, params)

  defp render_page(conn, user_id, params) do
    with {:ok, page} <-
           GetTrainingHistory.call(conn.assigns.tenant_context, user_id, Map.drop(params, [:id])) do
      json(conn, page)
    end
  end
end
