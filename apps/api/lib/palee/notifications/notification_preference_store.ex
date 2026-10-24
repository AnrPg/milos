defmodule Palee.Notifications.NotificationPreferenceStore do
  @moduledoc "Facade over the notification-preference adapter; every call runs in the person's `RepoContext` session (ADR-199)."

  @behaviour Palee.Notifications.Ports.NotificationPreferenceStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :notification_preference_store)

  defp run(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def list(context), do: run(context, :list, [])
  @impl true
  def put(context, category, pairs, now), do: run(context, :put, [category, pairs, now])
end
