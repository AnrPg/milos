defmodule PaleeWeb.AdminPlanController do
  @moduledoc "ADR-170: the gym's or coach's platform plan, seats and notice (owners and admins)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.OrganizationPlan
  alias PaleeWeb.PlatformPlanJSON
  alias PaleeWeb.Schemas.PlatformPlans, as: S

  action_fallback PaleeWeb.FallbackController

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
