defmodule Palee.Application.PlatformPlanCatalog do
  @moduledoc """
  ADR-170: the platform's plans. Anyone reads the public catalog (pricing,
  the coach onboarding); vendors edit plans and put organizations on them in
  the platform console.
  """

  alias Palee.PlatformPlans

  def list_public(audience) when audience in [nil, "gym", "coach"],
    do: PlatformPlans.list_public_plans(audience)

  def list_public(_audience), do: {:error, :invalid_plan_audience}

  def list(platform_context), do: PlatformPlans.list_plans(platform_context)
  def create(platform_context, attrs), do: PlatformPlans.create_plan(platform_context, attrs)

  def update(platform_context, code, attrs),
    do: PlatformPlans.update_plan(platform_context, code, attrs)

  def subscriptions(platform_context),
    do: PlatformPlans.list_subscriptions(platform_context, :all)

  def assign(platform_context, organization_id, attrs),
    do: PlatformPlans.assign_plan(platform_context, organization_id, attrs)
end
