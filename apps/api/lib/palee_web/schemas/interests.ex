defmodule PaleeWeb.Schemas.Interests do
  @moduledoc "OpenAPI schemas of a person's interests (ADR-183)."

  alias Palee.Interests
  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  defdelegate body(schema), to: Community

  def interests do
    %Schema{
      title: "AccountInterests",
      type: :object,
      description:
        "Disciplines are keys of the box vocabulary (GET /box-vocabulary); level is a Partners level or null",
      properties: %{
        disciplines: %Schema{
          type: :array,
          items: %Schema{type: :string},
          maxItems: Interests.max_disciplines()
        },
        level: %Schema{type: :string, enum: Interests.levels(), nullable: true}
      },
      required: [:disciplines, :level]
    }
  end

  def response do
    %Schema{
      title: "AccountInterestsResponse",
      type: :object,
      properties: %{interests: interests()},
      required: [:interests]
    }
  end
end
