defmodule MilosTrainingWeb.ThemeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.GetPublicTheme
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Theme"])

  @theme_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

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
    with {:ok, payload} <- GetPublicTheme.call() do
      json(conn, payload)
    end
  end
end
