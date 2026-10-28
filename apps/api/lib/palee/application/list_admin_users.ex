defmodule Palee.Application.ListAdminUsers do
  @moduledoc false

  alias Palee.{Finance, Organizations}
  alias Palee.Application.{AuthorizeClientAccess, TenantUserAccess}
  alias Palee.Organizations.Domain.MembershipPolicy

  def call(params \\ %{}, tenant_context \\ nil) do
    query = params |> field(:q) |> normalize_query()
    role = params |> field(:role) |> normalize_role()
    limit = params |> field(:limit) |> normalize_integer(25, 1, 50)
    offset = params |> field(:offset) |> normalize_integer(0, 0, 10_000)

    roles_by_user = Organizations.member_roles_by_user(tenant_context)

    users =
      tenant_context
      |> TenantUserAccess.list_active_users()
      |> filter_scope(tenant_context)
      |> filter_role(role, roles_by_user)
      |> filter_query(query)
      |> Enum.sort_by(&String.downcase(&1.nickname))

    # ADR-217: only clients have a finance profile; staff are never looked up.
    finance =
      finance_summaries(
        tenant_context,
        Enum.filter(users, &client?(&1, roles_by_user))
      )

    entries =
      users
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(&directory_entry(&1, finance, roles_by_user))

    {:ok,
     %{
       users: entries,
       meta: %{
         total: length(users),
         limit: limit,
         offset: offset,
         has_more: offset + limit < length(users)
       }
     }}
  end

  # A coach with scope `:own` sees only their own clients (ADR-100).
  defp filter_scope(users, nil), do: users

  defp filter_scope(users, context) do
    case directory_scope(context) do
      :all -> users
      ids -> Enum.filter(users, &(&1.id in ids))
    end
  end

  defp directory_scope(context) do
    if Palee.Organizations.can?(context, :view_directory),
      do: AuthorizeClientAccess.client_ids(context, :view_directory),
      else: :all
  end

  defp finance_summaries(nil, _users), do: %{}
  defp finance_summaries(_tenant_context, []), do: %{}

  defp finance_summaries(tenant_context, users) do
    Finance.search_member_summaries(tenant_context, %{
      user_ids: Enum.map(users, & &1.id),
      limit: max(length(users), 1)
    })
  end

  # ADR-217: a person is shown by their roles in this gym (`roles`, the
  # primary `role`, head coach via `coach_scope`), never by the account-wide
  # `users.role`; `staff` marks anyone holding a staff role.
  defp directory_entry(user, finance, roles_by_user) do
    facts = Map.get(roles_by_user, user.id)
    roles = tenant_roles(facts)
    profile = Map.get(finance, user.id)
    membership = if profile, do: profile.membership, else: nil

    %{
      id: user.id,
      nickname: user.nickname,
      avatar_url: user.avatar_url,
      role: primary_role(roles, user),
      roles: Enum.map(roles, &to_string/1),
      coach_scope: facts && facts.coach_scope && to_string(facts.coach_scope),
      staff: MembershipPolicy.staff?(roles),
      client: MembershipPolicy.client?(roles),
      account_status: "active",
      joined_at: timestamp(user.inserted_at),
      finance_status: if(membership, do: to_string(Map.get(membership, :status)), else: nil),
      attention_count: 0
    }
  end

  defp tenant_roles(%{roles: roles}) when is_list(roles), do: roles
  defp tenant_roles(_facts), do: []

  defp primary_role([], user), do: to_string(user.role)
  defp primary_role(roles, _user), do: roles |> MembershipPolicy.primary_role() |> to_string()

  defp client?(user, roles_by_user),
    do: roles_by_user |> Map.get(user.id) |> tenant_roles() |> MembershipPolicy.client?()

  defp filter_role(users, nil, _roles_by_user), do: users

  defp filter_role(users, role, roles_by_user) do
    Enum.filter(users, fn user ->
      roles = roles_by_user |> Map.get(user.id) |> tenant_roles()

      case role do
        "staff" -> MembershipPolicy.staff?(roles)
        "client" -> MembershipPolicy.client?(roles)
        role -> Enum.any?(roles, &(to_string(&1) == role))
      end
    end)
  end

  defp filter_query(users, nil), do: users

  defp filter_query(users, query),
    do: Enum.filter(users, &Palee.Identity.Domain.NameSearch.matches?(&1, query))

  defp normalize_query(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      query -> query
    end
  end

  defp normalize_query(_value), do: nil
  @role_filters ["staff", "client" | Enum.map(MembershipPolicy.roles(), &Atom.to_string/1)]

  defp normalize_role(role) when role in @role_filters, do: role
  defp normalize_role(_role), do: nil

  defp normalize_integer(value, _default, minimum, maximum) when is_integer(value),
    do: value |> max(minimum) |> min(maximum)

  defp normalize_integer(value, default, minimum, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_integer(integer, default, minimum, maximum)
      _ -> default
    end
  end

  defp normalize_integer(_value, default, _minimum, _maximum), do: default
  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
