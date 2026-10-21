defmodule MilosTrainingWeb.AdminPlanController do
  @moduledoc "ADR-170: the gym's or coach's platform plan, seats and notice (owners and admins)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.OrganizationPlan
  alias MilosTrainingWeb.PlatformPlanJSON
  alias MilosTrainingWeb.Schemas.PlatformPlans, as: S

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin plan"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "The organization's platform plan with seats used",
    responses: [ok: {"Plan", "application/json", S.organization_plan()}]
  )

  def show(conn, _params) do
    with {:ok, view} <- OrganizationPlan.get(conn.assigns.tenant_context) do
      json(conn, PlatformPlanJSON.organization_plan(view))
    end
  end
end
