defmodule MilosTrainingWeb.WorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Workouts
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  @id_param %Parameter{
    name: :id,
    in: :path,
    description: "Workout ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:show,
    summary: "Get a master workout",
    parameters: [@id_param],
    responses: [
      ok:
        {"Workout", "application/json",
         %Schema{
           type: :object,
           properties: %{workout: %Schema{type: :object, additionalProperties: true}},
           required: [:workout]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:scales,
    summary: "Get materialized workout scale instances",
    parameters: [@id_param],
    responses: [
      ok:
        {"Materialized scales", "application/json",
         %Schema{
           type: :object,
           properties: %{
             workout: %Schema{type: :object, additionalProperties: true},
             scales: %Schema{
               type: :array,
               items: %Schema{type: :object, additionalProperties: true}
             }
           },
           required: [:workout, :scales]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def show(conn, %{"id" => id}) do
    case Workouts.get_workout(id) do
      nil -> {:error, :not_found}
      workout -> json(conn, %{workout: workout})
    end
  end

  def scales(conn, %{"id" => id}) do
    case Workouts.materialize_workout(id) do
      nil -> {:error, :not_found}
      payload -> json(conn, payload)
    end
  end
end
