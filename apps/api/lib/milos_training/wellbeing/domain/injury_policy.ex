defmodule MilosTraining.Wellbeing.Domain.InjuryPolicy do
  @user_visible "user_and_admin"

  def self_report_params(params) when is_map(params) do
    params
    |> string_key_map()
    |> Map.drop(["user_id", "reported_by_id", "reported_by_role", "status", "healed_on"])
    |> Map.put("visibility", @user_visible)
  end

  def owned_by_user?(%{user_id: user_id}, user_id), do: true
  def owned_by_user?(_injury, _user_id), do: false

  defp string_key_map(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
