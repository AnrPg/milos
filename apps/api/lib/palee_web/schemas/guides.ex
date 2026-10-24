defmodule PaleeWeb.Schemas.Guides do
  @moduledoc "OpenAPI schemas of in-app walkthrough progress (ADR-193)."

  alias OpenApiSpex.Schema
  alias Palee.Guides

  def guide_id,
    do: %Schema{
      type: :string,
      pattern: Guides.id_pattern(),
      description: "The web app's guide id, e.g. `shop_staff`."
    }

  def status, do: %Schema{type: :string, enum: Guides.statuses()}

  def progress do
    %Schema{
      title: "GuideProgress",
      type: :object,
      required: [
        :completed_at,
        :guide_id,
        :runs,
        :started_at,
        :status,
        :step,
        :updated_at,
        :version
      ],
      properties: %{
        guide_id: guide_id(),
        version: %Schema{type: :integer, minimum: 1, maximum: Guides.max_version()},
        status: status(),
        step: %Schema{
          type: :integer,
          minimum: 0,
          maximum: Guides.max_step(),
          description: "The step reached in the current run, from 0."
        },
        runs: %Schema{type: :integer, minimum: 1, description: "How many times it was started."},
        started_at: %Schema{type: :string, format: :"date-time"},
        completed_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "The first finish of the current run."
        },
        updated_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  def progress_list do
    %Schema{
      title: "GuideProgressList",
      type: :object,
      required: [:guides],
      properties: %{guides: %Schema{type: :array, items: progress()}}
    }
  end

  def update_request do
    %Schema{
      title: "GuideProgressUpdate",
      type: :object,
      required: [:status],
      properties: %{
        status: status(),
        step: %Schema{type: :integer, minimum: 0, maximum: Guides.max_step(), default: 0},
        version: %Schema{
          type: :integer,
          minimum: 1,
          maximum: Guides.max_version(),
          default: 1,
          description: "A newer version than the stored one starts a new run."
        }
      }
    }
  end
end
