defmodule PaleeWeb.AdminOnboardingController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.AdminOnboarding
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Onboarding"])
  security([%{"bearerAuth" => []}])

  # Gym steps (ADR-221 adds `page`) and an independent coach's (ADR-170).
  @steps ~w(timezone settings classes packages workout page invite tour profile sessions team bootcamp)

  @checklist_schema %Schema{
    title: "AdminOnboardingChecklist",
    type: :object,
    properties: %{
      audience: %Schema{type: :string, enum: ["gym", "coach"]},
      steps: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, enum: @steps},
            done: %Schema{type: :boolean},
            auto: %Schema{type: :boolean},
            skipped: %Schema{type: :boolean}
          },
          required: [:id, :done, :auto, :skipped]
        }
      },
      completed_count: %Schema{type: :integer},
      total: %Schema{type: :integer},
      finished: %Schema{type: :boolean},
      dismissed: %Schema{type: :boolean},
      tour_completed: %Schema{type: :boolean}
    },
    required: [
      :audience,
      :steps,
      :completed_count,
      :total,
      :finished,
      :dismissed,
      :tour_completed
    ]
  }

  operation(:show,
    summary: "Get the admin onboarding checklist",
    responses: [ok: {"Checklist", "application/json", @checklist_schema}]
  )

  operation(:update,
    summary: "Complete, skip or reopen a step, dismiss the popup or record the finished tour",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              action: %Schema{
                type: :string,
                enum: ~w(complete skip reopen dismiss restore tour_completed)
              },
              step: %Schema{
                type: :string,
                enum: @steps
              }
            },
            required: [:action]
          }
        }
      }
    },
    responses: [ok: {"Checklist", "application/json", @checklist_schema}]
  )

  def show(conn, _params) do
    with {:ok, checklist} <- AdminOnboarding.get(conn.assigns.tenant_context) do
      json(conn, checklist)
    end
  end

  def update(conn, _params) do
    with {:ok, checklist} <- AdminOnboarding.update(conn.assigns.tenant_context, conn.body_params) do
      json(conn, checklist)
    end
  end
end
