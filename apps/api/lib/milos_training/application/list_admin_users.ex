defmodule MilosTraining.Application.ListAdminUsers do
  @moduledoc false

  alias MilosTraining.{Finance, Identity, Identity.RegistrationPolicy}

  def call(params \\ %{}) do
    query = params |> field(:q) |> normalize_query()
    role = params |> field(:role) |> normalize_role()
    limit = params |> field(:limit) |> normalize_integer(25, 1, 50)
    offset = params |> field(:offset) |> normalize_integer(0, 0, 10_000)

    users =
      Identity.list_all_users()
      |> filter_role(role)
      |> filter_query(query)
      |> Enum.sort_by(&String.downcase(&1.nickname))

    finance =
      Finance.search_member_summaries(%{
        user_ids: Enum.map(users, & &1.id),
        limit: max(length(users), 1)
      })

    entries =
      users
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(&directory_entry(&1, finance))

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

  defp directory_entry(user, finance) do
    profile = Map.get(finance, user.id)
    membership = if profile, do: profile.membership, else: nil

    %{
      id: user.id,
      nickname: user.nickname,
      avatar_url: user.avatar_url,
      role: to_string(user.role),
      account_status: "active",
      joined_at: timestamp(user.inserted_at),
      finance_status: if(membership, do: to_string(Map.get(membership, :status)), else: nil),
      attention_count: 0
    }
  end

  defp filter_role(users, nil), do: users
  defp filter_role(users, role), do: Enum.filter(users, &(to_string(&1.role) == role))

  defp filter_query(users, nil), do: users

  defp filter_query(users, query) do
    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.nickname), query) or
        String.contains?(user.normalized_nickname || "", query)
    end)
  end

  defp normalize_query(value) when is_binary(value) do
    case value |> RegistrationPolicy.normalize_nickname() do
      "" -> nil
      query -> query
    end
  end

  defp normalize_query(_value), do: nil
  defp normalize_role(role) when role in ["member", "athlete", "admin"], do: role
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
