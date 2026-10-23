defmodule PaleeWeb.Schemas.LocationScope do
  @moduledoc "OpenAPI shape of a staff branch scope (ADR-186)."

  alias OpenApiSpex.{Parameter, Schema}

  @doc """
  The page branch filter of a report (ADR-186 §7): comma-separated location
  ids, narrowed to the person's branches; absent means all of them.
  """
  def filter_parameter do
    %Parameter{
      name: :location_ids,
      in: :query,
      required: false,
      description: "ADR-186: comma-separated branch ids to filter by",
      schema: %Schema{type: :string, maxLength: 7400}
    }
  end

  @doc "The applied filter, echoed by a filtered report."
  def filter_schema, do: schema()

  @doc "Per-branch rows of a report (ADR-186 §7)."
  def splits_schema do
    %Schema{
      type: :array,
      description: "ADR-186: headline figures per branch, when two or more are shown",
      items: %Schema{type: :object, additionalProperties: true}
    }
  end

  @doc """
  The branches a new item applies to («Ισχύει για», ADR-186 §8): one item per
  branch for a class, series or appointment slot.
  """
  def targets_schema do
    %Schema{
      type: :array,
      maxItems: 200,
      description: "ADR-186: create one item at each of these branches",
      items: %Schema{type: :string, format: :uuid}
    }
  end

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
