defmodule MilosTraining.Identity.Domain.AdminProfilePolicy do
  @moduledoc false

  alias MilosTraining.Organizations.Domain.AdminPath

  @person_sections ~w(overview finance training_history prs scores health_incidents class_participation messages)

  def sections(:athlete), do: @person_sections ++ ["coaching_context", "admin_actions"]
  def sections(:member), do: @person_sections ++ ["admin_actions"]
  def sections(:admin), do: ~w(overview messages admin_actions)

  def operational_links(user, organization_slug \\ nil)

  def operational_links(%{id: id, role: role}, organization_slug) do
    %{
      messages: "/account/activity/chats",
      user_id: id
    }
    |> maybe_put(
      role in [:member, :athlete],
      :finance,
      AdminPath.admin_url("/admin/finance", organization_slug)
    )
    |> maybe_put(
      role == :member,
      :classes,
      AdminPath.admin_url("/admin/class-schedule", organization_slug)
    )
    |> maybe_put(
      role == :athlete,
      :personal_coaching,
      AdminPath.admin_url("/admin/coaching-assignments", organization_slug)
    )
  end

  def finance_available?(role), do: role in [:member, :athlete]
  def coaching_available?(role), do: role == :athlete

  defp maybe_put(map, true, key, value), do: Map.put(map, key, value)
  defp maybe_put(map, false, _key, _value), do: map
end
