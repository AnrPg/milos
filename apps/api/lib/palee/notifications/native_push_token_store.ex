defmodule Palee.Notifications.NativePushTokenStore do
  @moduledoc "Dispatches the native push token port to the configured adapter (ADR-171)."

  @behaviour Palee.Notifications.Ports.NativePushTokenStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_user_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  defp adapter, do: Application.fetch_env!(:palee, :native_push_token_store)

  @impl true
  def save_native_push_token(params), do: adapter().save_native_push_token(params)

  @impl true
  def list_native_push_tokens(user_id), do: adapter().list_native_push_tokens(user_id)

  @impl true
  def get_native_push_token(user_id, id), do: adapter().get_native_push_token(user_id, id)

  @impl true
  def delete_native_push_token(user_id, token),
    do: adapter().delete_native_push_token(user_id, token)

  @impl true
  def delete_native_push_token_by_id(user_id, id),
    do: adapter().delete_native_push_token_by_id(user_id, id)
end
