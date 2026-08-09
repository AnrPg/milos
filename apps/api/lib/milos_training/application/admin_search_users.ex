defmodule MilosTraining.Application.AdminSearchUsers do
  alias MilosTraining.Application.AdminMemberSearchIndex
  alias MilosTraining.{Finance, Identity, Identity.RegistrationPolicy, Organizations}

  def call(params) do
    call(params, nil)
  end

  def call(params, tenant_context) do
    query = normalize_query(params["q"] || params[:q])
    role = normalize_role(params["role"] || params[:role] || "all")
    allowed_user_ids = allowed_user_ids(tenant_context)

    membership_status =
      normalize_filter(params["membership_status"] || params[:membership_status])

    package_code = normalize_filter(params["package_code"] || params[:package_code])
    package_family = normalize_filter(params["package_family"] || params[:package_family])
    user_type = normalize_filter(params["user_type"] || params[:user_type])
    limit = normalize_limit(params["limit"] || params[:limit])

    if empty_search?(query, role, membership_status, package_code, package_family, user_type) do
      {:ok, %{users: [], meta: %{limit: limit, empty_search: true}}}
    else
      search_params =
        %{
          query: query,
          role: role,
          membership_status: membership_status,
          package_code: package_code,
          package_family: package_family,
          user_type: user_type,
          limit: limit
        }
        |> maybe_put_organization_id(tenant_context)
        |> maybe_put_allowed_user_ids(allowed_user_ids)

      case search_with_index(search_params) do
        {:ok, payload} ->
          {:ok,
           payload
           |> filter_index_payload(Map.get(search_params, :allowed_user_ids))
           |> put_in([:meta, :empty_search], false)}

        {:error, _reason} ->
          {:ok, fallback_search(search_params)}
      end
    end
  end

  defp search_with_index(search_params) do
    with {:ok, %{users: users, meta: meta}} <- AdminMemberSearchIndex.search(search_params) do
      {:ok, %{users: users, meta: Map.merge(%{limit: search_params.limit}, meta)}}
    end
  end

  defp fallback_search(search_params) do
    candidates =
      Identity.list_all_users()
      |> Enum.reject(&(&1.role == :admin))
      |> filter_allowed_users(Map.get(search_params, :allowed_user_ids))
      |> filter_role(search_params.role)
      |> filter_query(search_params.query)

    finance_summaries =
      search_member_summaries(
        Map.get(search_params, :organization_id),
        %{
          user_ids: Enum.map(candidates, & &1.id),
          membership_status: search_params.membership_status,
          user_type: search_params.user_type,
          package_code: search_params.package_code,
          package_family: search_params.package_family,
          limit: max(length(candidates), search_params.limit)
        }
      )

    users =
      candidates
      |> Enum.map(&with_finance_summary(&1, finance_summaries))
      |> filter_membership_status(search_params.membership_status)
      |> filter_package_code(search_params.package_code)
      |> filter_package_family(search_params.package_family)
      |> filter_user_type(search_params.user_type)
      |> Enum.take(search_params.limit)

    %{
      users: users,
      meta: %{
        limit: search_params.limit,
        empty_search: false,
        search_backend: "postgres_fallback"
      }
    }
  end

  defp search_member_summaries(nil, filters), do: Finance.search_member_summaries(filters)

  defp search_member_summaries(organization_id, filters) when is_binary(organization_id),
    do: Finance.search_member_summaries(%{organization_id: organization_id}, filters)

  defp allowed_user_ids(nil), do: nil

  defp allowed_user_ids(tenant_context) do
    tenant_context
    |> Organizations.list_active_membership_user_ids()
    |> MapSet.new()
  end

  defp maybe_put_organization_id(search_params, %Organizations.TenantContext{
         organization_id: organization_id
       }),
       do: Map.put(search_params, :organization_id, organization_id)

  defp maybe_put_organization_id(search_params, _tenant_context), do: search_params

  defp maybe_put_allowed_user_ids(search_params, nil), do: search_params

  defp maybe_put_allowed_user_ids(search_params, allowed_user_ids),
    do: Map.put(search_params, :allowed_user_ids, allowed_user_ids)

  defp filter_index_payload(payload, nil), do: payload

  defp filter_index_payload(payload, allowed_user_ids) do
    Map.update(payload, :users, [], fn users ->
      Enum.filter(users, fn user -> MapSet.member?(allowed_user_ids, user.id) end)
    end)
  end

  defp filter_allowed_users(users, nil), do: users

  defp filter_allowed_users(users, allowed_user_ids) do
    Enum.filter(users, &MapSet.member?(allowed_user_ids, &1.id))
  end

  defp filter_role(users, "all"), do: users

  defp filter_role(users, role) do
    Enum.filter(users, &(to_string(&1.role) == role))
  end

  defp filter_query(users, nil), do: users

  defp filter_query(users, query) do
    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.nickname), query) or
        String.contains?(user.normalized_nickname || "", query)
    end)
  end

  defp with_finance_summary(user, finance_summaries) do
    profile = Map.get(finance_summaries, user.id)
    membership = if profile, do: profile.membership, else: nil

    %{
      id: user.id,
      nickname: user.nickname,
      identity_role: to_string(user.role),
      membership: membership,
      package_subscriptions: if(profile, do: profile.package_subscriptions, else: []),
      active_package_subscription: if(profile, do: profile.active_package_subscription, else: nil)
    }
  end

  defp filter_membership_status(users, nil), do: users

  defp filter_membership_status(users, status) do
    Enum.filter(users, fn user -> membership_field(user, :status) == status end)
  end

  defp filter_package_code(users, nil), do: users

  defp filter_package_code(users, package_code) do
    Enum.filter(users, fn user ->
      Enum.any?(user.package_subscriptions, &(&1.package_code_snapshot == package_code))
    end)
  end

  defp filter_package_family(users, nil), do: users

  defp filter_package_family(users, package_family) do
    Enum.filter(users, fn user ->
      Enum.any?(user.package_subscriptions, &(&1.package_family_snapshot == package_family))
    end)
  end

  defp filter_user_type(users, nil), do: users

  defp filter_user_type(users, user_type) do
    Enum.filter(users, fn user -> membership_field(user, :user_type_snapshot) == user_type end)
  end

  defp membership_field(%{membership: nil}, _field), do: nil
  defp membership_field(%{membership: membership}, field), do: Map.get(membership, field)

  defp normalize_role(role) when role in ["member", "athlete", "all"], do: role
  defp normalize_role(_role), do: "all"

  defp normalize_query(nil), do: nil
  defp normalize_query(""), do: nil
  defp normalize_query(query), do: RegistrationPolicy.normalize_nickname(query)

  defp normalize_filter(nil), do: nil
  defp normalize_filter(""), do: nil
  defp normalize_filter("all"), do: nil
  defp normalize_filter(value), do: value

  defp normalize_limit(limit) when is_integer(limit), do: limit |> min(50) |> max(1)

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> normalize_limit(value)
      _ -> 10
    end
  end

  defp normalize_limit(_limit), do: 10

  defp empty_search?(nil, "all", nil, nil, nil, nil), do: true

  defp empty_search?(
         _query,
         _role,
         _membership_status,
         _package_code,
         _package_family,
         _user_type
       ),
       do: false
end
