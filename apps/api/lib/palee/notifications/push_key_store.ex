defmodule Palee.Notifications.PushKeyStore do
  @moduledoc false
  @behaviour Palee.Notifications.Ports.PushKeyStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_user_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  defp adapter, do: Application.fetch_env!(:palee, :push_key_store)

  @impl true
  def get, do: adapter().get()

  @impl true
  def put_keys_if_missing(keys), do: adapter().put_keys_if_missing(keys)

  @impl true
  def replace_keys(keys), do: adapter().replace_keys(keys)

  @impl true
  def put_subject(subject), do: adapter().put_subject(subject)

  @impl true
  def device_stats, do: adapter().device_stats()

  @impl true
  def forget_all_devices, do: adapter().forget_all_devices()
end
