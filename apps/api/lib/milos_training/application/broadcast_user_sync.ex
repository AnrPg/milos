defmodule MilosTraining.Application.BroadcastUserSync do
  def for_user(user_id, scopes, opts \\ []) when is_binary(user_id) do
    for_users([user_id], scopes, opts)
  end

  def for_users(user_ids, scopes, opts \\ []) when is_list(user_ids) do
    payload = %{
      scopes: normalize_scopes(scopes),
      reason: Keyword.get(opts, :reason, "data_changed"),
      payload: Keyword.get(opts, :payload, %{})
    }

    user_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      Phoenix.PubSub.broadcast(
        MilosTraining.PubSub,
        "user:sync",
        {:user_sync, Map.put(payload, :user_id, user_id)}
      )
    end)

    :ok
  end

  defp normalize_scopes(scopes) do
    scopes
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
