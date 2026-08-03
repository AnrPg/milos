defmodule MilosTraining.Application.AuthorizeFinanceEntitlement do
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.EntitlementPolicy

  def call(%{id: user_id, role: role}, request) when is_map(request) do
    entitlement = Finance.get_effective_entitlement(user_id)
    mode = entitlement_mode(entitlement)

    entitlement
    |> EntitlementPolicy.authorize(request, mode: mode, actor_role: role)
    |> add_denial_details(request)
  end

  def call(user_id, capability) do
    user_id
    |> Finance.get_entitlement()
    |> EntitlementPolicy.authorize(capability)
  end

  def execution_request(%{source: "class_booking"}),
    do: %{channel: :in_person, capability: :execute_class_workouts}

  def execution_request(%{source: "assigned"}),
    do: %{channel: :personal_programming, capability: :execute_assigned_workouts}

  def execution_request(%{source: "self_selected"}),
    do: %{channel: :workout_library, capability: :execute_library_workouts}

  defp entitlement_mode(%{enforcement_mode: mode}) when is_atom(mode), do: mode
  defp entitlement_mode(_), do: :observe

  defp add_denial_details({:error, :finance_channel_not_included}, request),
    do: {:error, :finance_channel_not_included, %{channel: value(request, :channel)}}

  defp add_denial_details({:error, :finance_capability_not_included}, request),
    do: {:error, :finance_capability_not_included, %{capability: value(request, :capability)}}

  defp add_denial_details({:error, :finance_allowance_not_included}, request),
    do: {:error, :finance_allowance_not_included, %{allowance: value(request, :allowance)}}

  defp add_denial_details(result, _request), do: result

  defp value(request, key), do: Map.get(request, key) || Map.get(request, Atom.to_string(key))
end
