defmodule PaleeWeb.PlatformPlanController do
  @moduledoc """
  ADR-170: the platform's plans. `index_public` is the public catalog;
  everything else is the vendors' platform console (prices start as
  placeholders, brief §10 Q2).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PlatformPlanCatalog
  alias PaleeWeb.PlatformPlanJSON
  alias PaleeWeb.Schemas.PlatformPlans, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Platform plans"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @code %Parameter{name: :code, in: :path, required: true, schema: %Schema{type: :string}}
  @organization_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index_public,
    summary: "Active public platform plans (pricing, coach onboarding)",
    security: [],
    parameters: [
      %Parameter{
        name: :audience,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["gym", "coach"]}
      }
    ],
    responses: [ok: {"Plans", "application/json", S.plans()}]
  )

  def index_public(conn, params) do
    with {:ok, plans} <- PlatformPlanCatalog.list_public(audience(params)) do
      json(conn, %{plans: Enum.map(plans, &PlatformPlanJSON.plan/1)})
    end
  end

  operation(:index,
    summary: "Every platform plan (vendors)",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Plans", "application/json", S.plans()}]
  )

  def index(conn, _params) do
    with {:ok, plans} <- PlatformPlanCatalog.list(conn.assigns.platform_context) do
      json(conn, %{plans: Enum.map(plans, &PlatformPlanJSON.plan/1)})
    end
  end

  operation(:create,
    summary: "Add a platform plan (vendors)",
    security: [%{"bearerAuth" => []}],
    request_body: S.plan_body([:code, :audience, :name]),
    responses: [created: {"Plan", "application/json", S.plan()}]
  )

  def create(conn, _params) do
    with {:ok, plan} <-
           PlatformPlanCatalog.create(conn.assigns.platform_context, conn.body_params) do
      conn |> put_status(:created) |> json(PlatformPlanJSON.plan(plan))
    end
  end

  operation(:update,
    summary: "Change a plan's name, limits, prices, trial or visibility (vendors)",
    security: [%{"bearerAuth" => []}],
    parameters: [@code],
    request_body: S.plan_body([]),
    responses: [ok: {"Plan", "application/json", S.plan()}]
  )

  def update(conn, %{code: code}) do
    attrs = Map.drop(conn.body_params, [:code, :audience])

    with {:ok, plan} <- PlatformPlanCatalog.update(conn.assigns.platform_context, code, attrs) do
      json(conn, PlatformPlanJSON.plan(plan))
    end
  end

  operation(:subscriptions,
    summary: "The plan every organization is on (vendors)",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Subscriptions", "application/json", S.subscriptions()}]
  )

  def subscriptions(conn, _params) do
    with {:ok, subscriptions} <- PlatformPlanCatalog.subscriptions(conn.assigns.platform_context) do
      now = DateTime.utc_now()

      json(conn, %{
        subscriptions: Enum.map(subscriptions, &PlatformPlanJSON.subscription(&1, now))
      })
    end
  end

  operation(:assign,
    summary: "Put an organization on a plan with a status (vendors)",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_id],
    request_body: S.assignment_body(),
    responses: [ok: {"Subscription", "application/json", S.subscription()}]
  )

  def assign(conn, %{id: organization_id}) do
    with {:ok, subscription} <-
           PlatformPlanCatalog.assign(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      json(conn, PlatformPlanJSON.subscription(subscription))
    end
  end

  defp audience(%{audience: audience}), do: audience
  defp audience(_params), do: nil
end
