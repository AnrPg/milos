defmodule PaleeWeb.Schemas.LocationScope do
  @moduledoc "OpenAPI shape of a staff branch scope (ADR-186)."

  alias OpenApiSpex.Schema

  def schema do
    %Schema{
      type: :object,
      description:
        "ADR-186: the branches a staff member works at; all_locations means every branch",
      properties: %{
        all_locations: %Schema{type: :boolean},
        location_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
      },
      required: [:all_locations, :location_ids]
    }
  end

  def request_schema do
    %Schema{
      type: :object,
      properties: %{
        all_locations: %Schema{type: :boolean},
        location_ids: %Schema{
          type: :array,
          maxItems: 200,
          items: %Schema{type: :string, format: :uuid}
        }
      }
    }
  end
end
