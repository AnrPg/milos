defmodule MilosTrainingWeb.HealthController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Infrastructure.Readiness
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Health"])

  operation(:index,
    summary: "Read API health",
    description: "Returns the API health status for local and container checks.",
    responses: [
      ok:
        {"Health response", "application/json",
         %Schema{
           type: :object,
           properties: %{
             status: %Schema{type: :string, example: "ok"},
             version: %Schema{type: :string, example: "0.1.0"},
             dependencies: %Schema{
               type: :object,
               properties: %{
                 database: %Schema{type: :string, example: "ok"},
                 redis: %Schema{type: :string, example: "ok"}
               },
               required: [:database, :redis]
             }
           },
           required: [:status, :version, :dependencies]
         }},
      service_unavailable:
        {"Readiness failure", "application/json",
         %Schema{
           type: :object,
           properties: %{
             status: %Schema{type: :string, example: "error"},
             version: %Schema{type: :string, example: "0.1.0"},
             dependencies: %Schema{
               type: :object,
               properties: %{
                 database: %Schema{type: :string, example: "error"},
                 redis: %Schema{type: :string, example: "error"}
               },
               required: [:database, :redis]
             }
           },
           required: [:status, :version, :dependencies]
         }}
    ]
  )

  def index(conn, _params) do
    version =
      :milos_training
      |> Application.spec(:vsn)
      |> to_string()

    case Readiness.status() do
      {:ok, checks} ->
        json(conn, %{status: "ok", version: version, dependencies: stringify_checks(checks)})

      {:error, checks} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", version: version, dependencies: stringify_checks(checks)})
    end
  end

  defp stringify_checks(checks) do
    Map.new(checks, fn {name, status} -> {name, Atom.to_string(status)} end)
  end
end
