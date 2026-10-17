defmodule MilosTrainingWeb.Schemas.SavedFilters do
  @moduledoc "OpenAPI schemas of remembered filters (ADR-151)."

  alias MilosTraining.Identity
  alias OpenApiSpex.Schema

  def surface, do: %Schema{type: :string, enum: Identity.filter_surfaces()}

  def params,
    do: %Schema{
      type: :object,
      additionalProperties: true,
      description: "The surface's filter values; the surface's query validates them."
    }

  def filters do
    %Schema{
      title: "SavedFilters",
      type: :object,
      required: [:surface, :last_used, :saved],
      properties: %{
        surface: surface(),
        last_used: %Schema{params() | nullable: true},
        saved: %Schema{
          type: :array,
          items: %Schema{
            title: "SavedFilter",
            type: :object,
            required: [:id, :name, :params, :last_used_at],
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              name: %Schema{type: :string},
              params: params(),
              last_used_at: %Schema{type: :string, format: :"date-time"}
            }
          }
        }
      }
    }
  end

  def remember_request do
    %Schema{
      title: "RememberFilterRequest",
      type: :object,
      required: [:params],
      properties: %{params: params()}
    }
  end

  def save_request do
    %Schema{
      title: "SaveFilterRequest",
      type: :object,
      required: [:name, :params],
      properties: %{name: %Schema{type: :string, minLength: 1, maxLength: 40}, params: params()}
    }
  end
end
