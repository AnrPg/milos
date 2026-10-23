defmodule Palee.Notifications.Commands.CreateNotification do
  @moduledoc """
  Writes an in-app notification (the push follows it). ADR-184: a mock
  person of a demo business never gets one, and a demo business notifies
  nobody outside its own staff: such a notification is `{:ok, :suppressed}`
  and nothing is written or pushed.
  """

  alias Palee.BusinessAccounts
  alias Palee.Notifications.NotificationStore

  def call(params) do
    if suppressed?(params),
      do: {:ok, :suppressed},
      else: NotificationStore.create_notification(params)
  end

  defp suppressed?(params) do
    BusinessAccounts.notification_suppressed?(
      field(params, :organization_id),
      field(params, :user_id)
    )
  end

  defp field(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
