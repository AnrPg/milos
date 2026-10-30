defmodule PaleeWeb.Schemas.Cleaning do
  @moduledoc "OpenAPI schemas for the cleaning log (ADR-102)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}

  def uuid, do: @uuid

  def area do
    %Schema{
      title: "CleaningArea",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        tasks: %Schema{type: :array, items: %Schema{type: :string}},
        archived_at: @time,
        last_cleaned_at: @time,
        # ADR-202: an area is a space; where it is drawn on a floor plan.
        floor_plan_id: %Schema{type: :string, format: :uuid, nullable: true},
        area: PaleeWeb.Schemas.Spaces.area(),
        # ADR-290: the room's visual cleaning checklist.
        points: %Schema{type: :array, items: PaleeWeb.Schemas.Spaces.cleaning_point()}
      },
      required: [:id, :name, :tasks]
    }
  end

  def entry do
    %Schema{
      title: "CleaningEntry",
      type: :object,
      properties: %{
        id: @uuid,
        area_id: @uuid,
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        nickname: %Schema{type: :string, nullable: true},
        started_at: %Schema{type: :string, format: :"date-time"},
        finished_at: @time,
        tasks_done: %Schema{type: :array, items: %Schema{type: :string}},
        note: %Schema{type: :string, nullable: true},
        point_results: %Schema{type: :array, items: point_result()}
      },
      required: [:id, :area_id, :started_at, :tasks_done]
    }
  end

  @doc "ADR-290: what the janitor answered for a cleaning point, as the point read then."
  def point_result do
    %Schema{
      title: "CleaningPointResult",
      type: :object,
      properties: %{
        point_id: @uuid,
        instruction: %Schema{type: :string},
        media_id: @uuid,
        url: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string, enum: ["cleaned", "not_cleaned"]},
        note: %Schema{type: :string, nullable: true},
        after_media_id: %Schema{type: :string, format: :uuid, nullable: true},
        after_url: %Schema{type: :string, nullable: true}
      },
      required: [:point_id, :instruction, :status]
    }
  end

  @doc "ADR-290: one answer when finishing a cleaning."
  def point_answer do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        point_id: @uuid,
        status: %Schema{type: :string, enum: ["cleaned", "not_cleaned"]},
        note: %Schema{type: :string, maxLength: 1000, nullable: true},
        after_media_id: %Schema{type: :string, format: :uuid, nullable: true}
      },
      required: [:point_id, :status]
    }
  end

  def area_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        tasks: %Schema{type: :array, maxItems: 30, items: %Schema{type: :string, maxLength: 120}}
      }
    }
  end

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def many(key, schema), do: one(key, %Schema{type: :array, items: schema})
end
