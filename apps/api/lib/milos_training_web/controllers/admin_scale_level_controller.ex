defmodule MilosTrainingWeb.AdminScaleLevelController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ReplaceScaleLevels
  alias MilosTraining.Workouts
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Scale Levels"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update]

  operation(:index,
    summary: "List configured scale levels",
    responses: [
      ok:
        {"Scale levels", "application/json",
         %Schema{
           type: :object,
           properties: %{
             scale_levels: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   slug: %Schema{type: :string},
                   label: %Schema{type: :string},
                   sort_order: %Schema{type: :integer},
                   is_active: %Schema{type: :boolean}
                 },
                 required: [:id, :slug, :label, :sort_order, :is_active]
               }
             }
           },
           required: [:scale_levels]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:update,
    summary: "Replace configured scale levels",
    request_body: %RequestBody{
      description: "Scale levels payload",
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              scale_levels: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  properties: %{
                    slug: %Schema{type: :string},
                    label: %Schema{type: :string},
                    sort_order: %Schema{type: :integer}
                  },
                  required: [:slug, :label, :sort_order]
                }
              }
            },
            required: [:scale_levels]
          }
        }
      }
    },
    responses: [
      ok:
        {"Scale levels", "application/json",
         %Schema{
           type: :object,
           properties: %{
             scale_levels: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:scale_levels]
         }},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             errors: %Schema{
               type: :object,
               additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
             }
           },
           required: [:errors]
         }}
    ]
  )

  def index(conn, _params) do
    json(conn, %{scale_levels: Workouts.list_scale_levels()})
  end

  def update(conn, params) do
    levels =
      Map.get(conn.body_params, "scale_levels") ||
        Map.get(conn.body_params, :scale_levels) ||
        Map.get(params, "scale_levels") ||
        Map.get(params, :scale_levels) ||
        []

    case ReplaceScaleLevels.call(levels) do
      {:ok, scale_levels} -> json(conn, %{scale_levels: scale_levels})
      error -> error
    end
  end
end
