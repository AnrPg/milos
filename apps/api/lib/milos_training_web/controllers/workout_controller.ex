defmodule MilosTrainingWeb.WorkoutController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetMaterializedWorkout, GetPublishedWorkout}
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
    with {:ok, workout} <- GetPublishedWorkout.call(id) do
      json(conn, %{workout: workout})
    end
  end

  def scales(conn, %{"id" => id}) do
    with {:ok, payload} <- GetMaterializedWorkout.call(id) do
      json(conn, payload)
    end
  end
end
