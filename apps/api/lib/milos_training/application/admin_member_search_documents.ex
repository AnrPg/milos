defmodule MilosTraining.Application.AdminMemberSearchDocuments do
  alias MilosTraining.{Finance, Identity, Organizations}

  # TD-092: the rebuild runs from a cron job with no session scope. Memberships
  # and finance rows are tenant data, so each active gym is visited in its own
  # scope; unscoped, both reads were empty under the production runtime role
  # and every document lost its gyms (the index then matched nobody).
  def build_all do
    users =
      Identity.list_all_users()
      |> Enum.reject(&(&1.role == :admin))

    per_organization =
      Enum.map(Organizations.list_active_organizations_for_system(), &organization_members/1)

    organization_ids_by_user =
      for {organization_id, member_ids, _summaries} <- per_organization,
          user_id <- member_ids,
          reduce: %{} do
        acc -> Map.update(acc, user_id, [organization_id], &(&1 ++ [organization_id]))
      end

    # A document holds one finance profile; the first gym listing the member
    # wins, as the single cross-tenant query did before.
    finance_summaries =
      Enum.reduce(per_organization, %{}, fn {_organization_id, _ids, summaries}, acc ->
        Map.merge(summaries, acc)
      end)

    Enum.map(users, fn user ->
      document(
        user,
        Map.get(finance_summaries, user.id),
        Map.get(organization_ids_by_user, user.id, [])
      )
    end)
  end

  defp organization_members(%{organization: %{id: organization_id}}) do
    member_ids = Organizations.list_active_membership_user_ids(organization_id)
    {organization_id, member_ids, member_summaries(organization_id, member_ids)}
  end

  defp member_summaries(_organization_id, []), do: %{}

  defp member_summaries(organization_id, member_ids) do
    Finance.search_member_summaries(%{organization_id: organization_id}, %{
      user_ids: member_ids,
      limit: length(member_ids)
    })
  end

  defp document(user, nil, organization_ids) do
    %{
      id: user.id,
      nickname: user.nickname,
      identity_role: to_string(user.role),
      searchable_text:
        [user.nickname, user.normalized_nickname] |> Enum.reject(&is_nil/1) |> Enum.join(" "),
      membership_status: nil,
      user_type: nil,
      package_codes: [],
      package_families: [],
      package_tags: [],
      organization_ids: organization_ids,
      membership: nil,
      package_subscriptions: [],
      active_package_subscription: nil
    }
  end

  defp document(user, profile, organization_ids) do
    subscriptions = profile.package_subscriptions || []

    %{
      id: user.id,
      nickname: user.nickname,
      identity_role: to_string(user.role),
      searchable_text: searchable_text(user, profile),
      membership_status: get_in(profile, [:membership, :status]),
      user_type: get_in(profile, [:membership, :user_type_snapshot]),
      package_codes: subscription_field_values(subscriptions, :package_code_snapshot),
      package_families: subscription_field_values(subscriptions, :package_family_snapshot),
      package_tags: package_tags(subscriptions),
      organization_ids: organization_ids,
      membership: profile.membership,
      package_subscriptions: subscriptions,
      active_package_subscription: profile.active_package_subscription
    }
  end

  defp searchable_text(user, profile) do
    subscriptions = profile.package_subscriptions || []

    [
      user.nickname,
      user.normalized_nickname,
      get_in(profile, [:membership, :status]),
      get_in(profile, [:membership, :user_type_snapshot])
      | subscription_field_values(subscriptions, :package_code_snapshot) ++
          subscription_field_values(subscriptions, :package_family_snapshot)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp subscription_field_values(subscriptions, field) do
    subscriptions
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp package_tags(subscriptions) do
    subscriptions
    |> Enum.flat_map(fn subscription ->
      subscription
      |> Map.get(:params_snapshot, %{})
      |> Map.get("tags", [])
      |> List.wrap()
    end)
    |> Enum.uniq()
  end
end
