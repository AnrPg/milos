defmodule MilosTraining.Application.AdminMemberSearchDocuments do
  alias MilosTraining.{Finance, Identity}

  def build_all do
    users =
      Identity.list_all_users()
      |> Enum.reject(&(&1.role == :admin))

    finance_summaries =
      Finance.search_member_summaries(%{
        user_ids: Enum.map(users, & &1.id),
        limit: length(users)
      })

    Enum.map(users, &document(&1, Map.get(finance_summaries, &1.id)))
  end

  defp document(user, nil) do
    %{
      id: user.id,
      nickname: user.nickname,
      identity_role: to_string(user.role),
      searchable_text: user.nickname,
      membership_status: nil,
      user_type: nil,
      package_codes: [],
      package_families: [],
      package_tags: [],
      membership: nil,
      package_subscriptions: [],
      active_package_subscription: nil
    }
  end

  defp document(user, profile) do
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
      membership: profile.membership,
      package_subscriptions: subscriptions,
      active_package_subscription: profile.active_package_subscription
    }
  end

  defp searchable_text(user, profile) do
    subscriptions = profile.package_subscriptions || []

    [
      user.nickname,
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
