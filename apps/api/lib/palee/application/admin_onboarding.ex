defmodule Palee.Application.AdminOnboarding do
  @moduledoc """
  Tenant admin first-run checklist: stored progress from Organizations plus
  setup signals read from the contexts that own each step. A gym and an
  independent coach (ADR-170) get different steps.
  """

  alias Palee.{Appointments, Community, Finance, Organizations, Scheduling, Workouts}

  def get(context) do
    with {:ok, state} <- Organizations.get_onboarding_state(context) do
      {:ok, checklist(context, state)}
    end
  end

  def update(context, params) do
    with :ok <- time_zone_step(context, value(params, :action), value(params, :step)),
         {:ok, state} <- Organizations.update_onboarding(context, params) do
      {:ok, checklist(context, state)}
    end
  end

  # ADR-176: the zone must be set, so its step cannot be skipped; completing
  # it confirms the zone the gym is on now (the device's guess or default).
  defp time_zone_step(_context, "skip", "timezone"), do: {:error, :time_zone_required}

  defp time_zone_step(context, "complete", "timezone") do
    zone = Organizations.organization_timezone(context.organization_id)

    with {:ok, _settings} <- Organizations.set_timezone(context, zone, "confirmed"), do: :ok
  end

  defp time_zone_step(_context, _action, _step), do: :ok

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp checklist(context, state) do
    audience = Organizations.onboarding_audience(context)
    Organizations.onboarding_checklist(state, signals(context, audience), audience)
  end

  defp signals(context, "coach") do
    %{
      "timezone" => time_zone_confirmed?(context),
      "profile" => published_profile?(context),
      "sessions" => present?(Appointments.list_slots(context, %{})),
      "packages" => present?(Finance.list_packages(context)),
      "bootcamp" => open_event?(context),
      "invite" => invited?(context)
    }
  end

  defp signals(context, _gym) do
    %{
      "timezone" => time_zone_confirmed?(context),
      "classes" => present?(Scheduling.list_class_types(context)),
      "packages" => present?(Finance.list_packages(context)),
      "workout" => present?(Workouts.list_workouts(context)),
      "page" => published_profile?(context),
      "invite" => invited?(context)
    }
  end

  # ADR-176: done once an admin confirmed the zone, never by a guess.
  defp time_zone_confirmed?(context),
    do: Organizations.timezone_status(context.organization_id).confirmed

  defp invited?(context),
    do: clients?(context) or present?(Organizations.list_active_invitations(context))

  # ADR-217: a client is someone holding a member or athlete role in the box;
  # the owner's own account (account-wide role "member") never counts.
  defp clients?(context) do
    context
    |> Organizations.list_client_user_ids()
    |> Enum.any?(&(&1 != context.user_id))
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
