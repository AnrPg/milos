defmodule Palee.Application.AdminOnboarding do
  @moduledoc """
  Tenant admin first-run checklist: stored progress from Organizations plus
  setup signals read from the contexts that own each step. A gym and an
  independent coach (ADR-170) get different steps.
  """

  alias Palee.Application.TenantUserAccess
  alias Palee.{Appointments, Community, Finance, Organizations, Scheduling, Workouts}

  def get(context) do
    with {:ok, state} <- Organizations.get_onboarding_state(context) do
      {:ok, checklist(context, state)}
    end
  end

  def update(context, params) do
    with {:ok, state} <- Organizations.update_onboarding(context, params) do
      {:ok, checklist(context, state)}
    end
  end

  defp checklist(context, state) do
    audience = Organizations.onboarding_audience(context)
    Organizations.onboarding_checklist(state, signals(context, audience), audience)
  end

  defp signals(context, "coach") do
    %{
      "profile" => published_profile?(context),
      "sessions" => present?(Appointments.list_slots(context, %{})),
      "packages" => present?(Finance.list_packages(context)),
      "bootcamp" => open_event?(context),
      "invite" => invited?(context)
    }
  end

  defp signals(context, _gym) do
    %{
      "classes" => present?(Scheduling.list_class_types(context)),
      "packages" => present?(Finance.list_packages(context)),
      "workout" => present?(Workouts.list_workouts(context)),
      "invite" => invited?(context)
    }
  end

  defp invited?(context),
    do: clients?(context) or present?(Organizations.list_active_invitations(context))

  defp clients?(context) do
    context
    |> TenantUserAccess.list_active_users()
    |> Enum.any?(&(&1.role in [:member, :athlete]))
  end

  defp published_profile?(context) do
    case Organizations.get_public_profile(context) do
      %{published_at: %DateTime{}} -> true
      _unpublished -> false
    end
  end

  defp open_event?(context) do
    context
    |> Community.list_events(%{
      organization_ids: [context.organization_id],
      open_only: true,
      limit: 1
    })
    |> present?()
  end

  defp present?({:ok, list}), do: present?(list)
  defp present?(list) when is_list(list), do: list != []
  defp present?(_other), do: false
end
