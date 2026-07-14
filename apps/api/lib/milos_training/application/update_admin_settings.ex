defmodule MilosTraining.Application.UpdateAdminSettings do
  alias MilosTraining.Application.{BroadcastUserSync, InvalidateLandingPages}
  alias MilosTraining.{Finance, Gamification, Identity}

  def call(params) do
    gamification_params = gamification_params(params)
    finance_params = finance_params(params)

    with {:ok, gamification_settings} <- maybe_update_gamification(gamification_params),
         {:ok, finance_settings} <- maybe_update_finance(finance_params) do
      InvalidateLandingPages.for_all_users()
      admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)
      BroadcastUserSync.for_users(admin_ids, ["admin_settings"], reason: "admin_settings_updated")

      {:ok,
       %{
         gamification: gamification_settings,
         finance: finance_settings
       }}
    end
  end

  defp maybe_update_gamification(params) when map_size(params) == 0 do
    {:ok, Gamification.get_settings()}
  end

  defp maybe_update_gamification(params), do: Gamification.update_settings(params)

  defp maybe_update_finance(params) when map_size(params) == 0 do
    {:ok, Finance.get_finance_settings()}
  end

  defp maybe_update_finance(params), do: Finance.update_finance_settings(params)

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
end
