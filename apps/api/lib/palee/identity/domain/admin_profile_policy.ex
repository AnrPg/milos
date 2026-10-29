defmodule Palee.Identity.Domain.AdminProfilePolicy do
  @moduledoc """
  Which sections and links a person's admin profile shows. ADR-217: it reads
  the person's roles in the business (a role set, ADR-099), never the
  account-wide `users.role`, which says "member" for every account, owners
  included. Finance belongs to clients only; staff never have a package.
  """

  alias Palee.Organizations.Domain.{AdminPath, MembershipPolicy}

  @person_sections ~w(overview finance training_history prs scores health_incidents class_participation messages)
  @staff_sections ~w(overview training_history prs scores class_participation messages admin_actions)

  def sections(roles) when is_list(roles) do
    cond do
      :athlete in roles -> @person_sections ++ ["coaching_context", "admin_actions"]
      MembershipPolicy.client?(roles) -> @person_sections ++ ["admin_actions"]
      true -> @staff_sections
    end
  end

  def sections(role) when is_atom(role), do: sections([role])

  def operational_links(user, roles, organization_slug \\ nil)

  def operational_links(%{id: id}, roles, organization_slug) do
    roles = List.wrap(roles)

    %{
      messages: "/messages",
      user_id: id
    }
    |> maybe_put(
      finance_available?(roles),
      :finance,
      AdminPath.admin_url("/admin/finance", organization_slug)
    )
    |> maybe_put(
      :member in roles,
      :classes,
      AdminPath.admin_url("/admin/class-schedule", organization_slug)
    )
    |> maybe_put(
      coaching_available?(roles),
      :personal_coaching,
      AdminPath.admin_url("/admin/coaching-assignments", organization_slug)
    )
  end

  def finance_available?(roles), do: MembershipPolicy.buyer?(roles)
  def coaching_available?(roles), do: :athlete in List.wrap(roles)

  defp maybe_put(map, true, key, value), do: Map.put(map, key, value)
  defp maybe_put(map, false, _key, _value), do: map
end
