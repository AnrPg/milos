defmodule MilosTraining.Notifications.Queries.ListInboxPage do
  alias MilosTraining.Notifications.Domain.InboxCursor
  alias MilosTraining.Notifications.NotificationStore

  @default_limit 20
  @max_limit 50

  def call(user_id, params \\ %{}) do
    with {:ok, cursor} <- InboxCursor.decode(param(params, :cursor)),
         {:ok, limit} <- normalize_limit(param(params, :limit)) do
      page = NotificationStore.list_inbox_page(user_id, limit: limit, cursor: cursor)

      {:ok,
       %{
         notifications: page.notifications,
         next_cursor: page.next_cursor
       }}
    end
  end

  defp normalize_limit(nil), do: {:ok, @default_limit}

  defp normalize_limit(limit) when is_integer(limit) and limit > 0,
    do: {:ok, min(limit, @max_limit)}

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {parsed, ""} when parsed > 0 -> {:ok, min(parsed, @max_limit)}
      _ -> {:error, :bad_request}
    end
  end

  defp normalize_limit(_limit), do: {:error, :bad_request}

  defp param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
