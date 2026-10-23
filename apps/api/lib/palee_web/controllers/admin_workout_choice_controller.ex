defmodule PaleeWeb.AdminWorkoutChoiceController do
  @moduledoc "The class form's WOD picker: suggestions and paged search (no whole-library loads)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.WorkoutChoices

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  @choice %Schema{
    title: "WorkoutChoice",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      type: %Schema{type: :string},
      icon: %Schema{type: :string, nullable: true},
      icon_source: %Schema{type: :string, nullable: true},
      folder_id: %Schema{type: :string, format: :uuid, nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :title, :type]
  }

  @choices %Schema{type: :array, items: @choice}

  operation(:search,
    summary: "Search published library WODs for the class form, a page at a time",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 200},
        description: "Words of the title"
      },
      %Parameter{
        name: :type,
        in: :query,
        required: false,
        schema: %Schema{type: :string},
        description: "Workout type"
      },
      %Parameter{
        name: :folder_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid},
        description: "Library folder"
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50},
        description: "Page size (default 20)"
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0},
        description: "Rows to skip"
      }
    ],
    responses: [
      ok:
        {"WOD choices", "application/json",
         %Schema{
           type: :object,
           properties: %{
             workouts: @choices,
             has_more: %Schema{type: :boolean},
             next_offset: %Schema{type: :integer, nullable: true}
           },
           required: [:workouts, :has_more, :next_offset]
         }}
    ]
  )

  def search(conn, params) do
    with {:ok, result} <- WorkoutChoices.search(conn.assigns.tenant_context, params) do
      json(conn, result)
    end
  end

  operation(:suggested,
    summary: "The WODs a coach most likely wants for a class on a gym day",
    parameters: [
      %Parameter{
        name: :date,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date},
        description: "The class's gym-local day (default today)"
      },
      %Parameter{
        name: :class_type_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid},
        description: "The class's type"
      }
    ],
    responses: [
      ok:
        {"Suggested WODs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             date: %Schema{type: :string, format: :date},
             same_day: @choices,
             recent: @choices,
             newest: @choices
           },
           required: [:date, :same_day, :recent, :newest]
         }}
    ]
  )

  def suggested(conn, params) do
    with {:ok, result} <- WorkoutChoices.suggested(conn.assigns.tenant_context, params) do
      json(conn, result)
    end
  end
end
