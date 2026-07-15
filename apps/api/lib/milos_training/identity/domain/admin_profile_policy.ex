defmodule MilosTraining.Identity.Domain.AdminProfilePolicy do
  @moduledoc false

  @person_sections ~w(overview finance training_history prs scores health_incidents class_participation messages)

  def sections(:athlete), do: @person_sections ++ ["coaching_context", "admin_actions"]
  def sections(:member), do: @person_sections ++ ["admin_actions"]
  def sections(:admin), do: ~w(overview messages admin_actions)

  def operational_links(%{id: id, role: role}) do
    %{
      messages: "/account/activity/chats",
      user_id: id
    }
    |> maybe_put(role in [:member, :athlete], :finance, "/admin/finance")
    |> maybe_put(role == :member, :classes, "/admin/class-schedule")
    |> maybe_put(role == :athlete, :personal_coaching, "/admin/coaching-assignments")
  end

  def finance_available?(role), do: role in [:member, :athlete]
  def coaching_available?(role), do: role == :athlete

  defp maybe_put(map, true, key, value), do: Map.put(map, key, value)
  defp maybe_put(map, false, _key, _value), do: map
end
