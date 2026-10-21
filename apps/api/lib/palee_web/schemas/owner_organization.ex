defmodule PaleeWeb.Schemas.OwnerOrganization do
  @moduledoc "OpenAPI shapes for the owner's gym actions (ADR-099)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  def organization do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        status: %Schema{type: :string}
      },
      required: [:id, :slug, :name, :status]
    }
  end

  def body(properties, required) do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{type: :object, properties: properties, required: required}
        }
      }
    }
  end
end
