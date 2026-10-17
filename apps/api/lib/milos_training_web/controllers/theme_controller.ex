defmodule MilosTrainingWeb.ThemeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.GetPublicTheme
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Theme"])

  @theme_slugs MilosTraining.Themes.slugs()

  @theme_schema %Schema{
    type: :object,
    properties: %{
      theme_slug: %Schema{type: :string, enum: @theme_slugs}
    },
    required: [:theme_slug]
  }

  operation(:show,
    summary: "Fetch active public UI theme",
    responses: [
      ok: {"Active theme", "application/json", @theme_schema}
    ]
  )

  def show(conn, _params) do
    organization_slug = conn |> get_req_header("x-organization-slug") |> List.first()

    with {:ok, payload} <- GetPublicTheme.call(organization_slug) do
      json(conn, payload)
    end
  end
end
