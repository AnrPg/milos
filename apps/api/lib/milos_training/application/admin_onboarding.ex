defmodule MilosTraining.Application.AdminOnboarding do
  @moduledoc """
  Tenant admin first-run checklist: stored progress from Organizations plus
  setup signals read from the contexts that own each step.
  """

  alias MilosTraining.Application.TenantUserAccess
  alias MilosTraining.{Finance, Organizations, Scheduling, Workouts}

  def get(context) do
    with {:ok, state} <- Organizations.get_onboarding_state(context) do
      {:ok, Organizations.onboarding_checklist(state, signals(context))}
    end
  end

  def update(context, params) do
    with {:ok, state} <- Organizations.update_onboarding(context, params) do
      {:ok, Organizations.onboarding_checklist(state, signals(context))}
    end
  end

  defp signals(context) do
    %{
      "classes" => present?(Scheduling.list_class_types(context)),
      "packages" => present?(Finance.list_packages(context)),
      "workout" => present?(Workouts.list_workouts(context)),
      "invite" => clients?(context) or present?(Organizations.list_active_invitations(context))
    }
  end

  defp clients?(context) do
    context
    |> TenantUserAccess.list_active_users()
    |> Enum.any?(&(&1.role in [:member, :athlete]))
  end

  defp present?({:ok, list}), do: present?(list)
  defp present?(list) when is_list(list), do: list != []
  defp present?(_other), do: false
end
