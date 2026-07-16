defmodule MilosTrainingWeb.ApiSpec do
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, Schema, SecurityScheme, Server}

  @spec spec() :: OpenApi.t()
  def spec do
    %OpenApi{
      info: %Info{
        title: "Milos Training API",
        version: "0.1.0",
        description: "Contract for the Milos Training backend API."
      },
      servers: [
        %Server{url: "/"}
      ],
      components: %Components{
        schemas: %{
          "SemanticError" => %Schema{
            type: :object,
            description: "Stable machine-readable API failure with English compatibility copy.",
            properties: %{
              code: %Schema{type: :string},
              error: %Schema{type: :string},
              params: %Schema{type: :object, additionalProperties: true}
            },
            required: [:code, :error]
          },
          "ValidationError" => %Schema{
            type: :object,
            properties: %{
              code: %Schema{type: :string, enum: ["validation_failed"]},
              errors: %Schema{type: :object, additionalProperties: true}
            },
            required: [:code, :errors]
          }
        },
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT"
          }
        }
      },
      paths: Paths.from_router(MilosTrainingWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
