defmodule Palee.Application.UpdateAdminSettings do
  alias Palee.Application.{
    BroadcastUserSync,
    GetAdminSettings,
    InvalidateLandingPages,
    TenantStaffRecipients
  }

  alias Palee.{Finance, Gamification, Organizations, Scheduling}

  def call(context, params) do
    do_call(context, params)
  end

  def call(_params), do: {:error, :organization_context_required}

  defp do_call(context, params) do
    gamification_params = gamification_params(params)
    finance_params = finance_params(params)
    scheduling_params = scheduling_params(params)
    workout_params = section_params(params, "workouts")

    with :ok <- maybe_update_provider(context, provider_params(params)),
         {:ok, gamification_settings} <- maybe_update_gamification(context, gamification_params),
         {:ok, finance_settings} <- maybe_update_finance(context, finance_params),
         {:ok, scheduling_settings} <- maybe_update_scheduling(context, scheduling_params),
         {:ok, workout_settings} <- maybe_update_workouts(context, workout_params) do
      InvalidateLandingPages.for_all_users()
      admin_ids = TenantStaffRecipients.user_ids(context)
      BroadcastUserSync.for_users(admin_ids, ["admin_settings"], reason: "admin_settings_updated")

      {:ok,
       %{
         gamification: gamification_settings,
         finance: finance_settings,
         scheduling: scheduling_settings,
         workouts: workout_settings,
         provider: GetAdminSettings.provider(context)
       }}
    end
  end

  # ADR-162: first, so an admin's save that tries it changes nothing.
  defp maybe_update_provider(_context, params) when map_size(params) == 0, do: :ok

  defp maybe_update_provider(context, params) do
    case Map.get(params, :kind, Map.get(params, "kind")) do
      nil -> :ok
      kind -> Organizations.put_provider_kind(context, kind)
    end
  end

  # TD-092: read in the gym's scope - unscoped the defaults came back.
  defp maybe_update_gamification(context, params) when map_size(params) == 0 do
    {:ok, Gamification.with_tenant_context(context, &Gamification.get_settings/0)}
  end

  defp maybe_update_gamification(context, params) do
    Gamification.with_tenant_context(context, fn -> Gamification.update_settings(params) end)
  end

  # Finance settings are tenant rows: without the context the write has no
  # organization and the first save for a gym fails.
  defp maybe_update_finance(context, params) when map_size(params) == 0 do
    {:ok, Finance.get_finance_settings(context)}
  end

  defp maybe_update_finance(context, params), do: Finance.update_finance_settings(context, params)

  defp maybe_update_scheduling(context, params) when map_size(params) == 0 do
    {:ok, Scheduling.get_settings(context)}
  end

  defp maybe_update_scheduling(context, params),
    do: Scheduling.update_settings(context, params)

  # ADR-163: workout-authoring defaults live in the organization settings map.
  defp maybe_update_workouts(context, params) when map_size(params) == 0,
    do: {:ok, Organizations.get_workout_settings(context)}

  defp maybe_update_workouts(context, params),
    do: Organizations.update_workout_settings(context, params)

  defp gamification_params(%{gamification: g}) when is_map(g), do: g
  defp gamification_params(%{"gamification" => g}) when is_map(g), do: g
  defp gamification_params(%{body: body}) when is_map(body), do: gamification_params(body)
  defp gamification_params(%{"body" => body}) when is_map(body), do: gamification_params(body)
  defp gamification_params(params) when is_map(params), do: params

  defp finance_params(%{finance: f}) when is_map(f), do: f
  defp finance_params(%{"finance" => f}) when is_map(f), do: f
  defp finance_params(%{body: body}) when is_map(body), do: finance_params(body)
  defp finance_params(%{"body" => body}) when is_map(body), do: finance_params(body)
  defp finance_params(_), do: %{}

  defp scheduling_params(%{scheduling: value}) when is_map(value), do: value
  defp scheduling_params(%{"scheduling" => value}) when is_map(value), do: value
  defp scheduling_params(%{body: body}) when is_map(body), do: scheduling_params(body)
  defp scheduling_params(%{"body" => body}) when is_map(body), do: scheduling_params(body)
  defp scheduling_params(_), do: %{}

  defp section_params(params, key) do
    case Map.get(params, key, Map.get(params, String.to_existing_atom(key))) do
      value when is_map(value) -> value
      _missing -> nested_section_params(params, key)
    end
  end

  defp nested_section_params(%{"body" => body}, key) when is_map(body),
    do: section_params(body, key)

  defp nested_section_params(%{body: body}, key) when is_map(body), do: section_params(body, key)
  defp nested_section_params(_params, _key), do: %{}

  defp provider_params(%{provider: value}) when is_map(value), do: value
  defp provider_params(%{"provider" => value}) when is_map(value), do: value
  defp provider_params(%{body: body}) when is_map(body), do: provider_params(body)
  defp provider_params(%{"body" => body}) when is_map(body), do: provider_params(body)
  defp provider_params(_), do: %{}
end
