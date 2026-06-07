defmodule MilosTrainingWeb.ApiSpec do
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

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
