defmodule Palee.Notifications.Commands.CreateNotification do
  @moduledoc """
  Writes an in-app notification (the push follows it). ADR-184: a mock
  person of a demo business never gets one, and a demo business notifies
  nobody outside its own staff. ADR-199: a person who switched the type's
  category off for the bell does not get it either. Either way the answer is
  `{:ok, :suppressed}` and nothing is written or pushed.

  Every in-app notification is written here, so this is where the bell
  preference is checked.
  """

  alias Palee.BusinessAccounts
  alias Palee.Notifications.NotificationStore
  alias Palee.Notifications.Queries.DeliversNotification

  def call(params) do
    if suppressed?(params) or muted?(params),
      do: {:ok, :suppressed},
      else: NotificationStore.create_notification(params)
  end

  defp suppressed?(params) do
    BusinessAccounts.notification_suppressed?(
      field(params, :organization_id),
      field(params, :user_id)
    )
  end

  defp muted?(params),
    do: not DeliversNotification.call(field(params, :user_id), field(params, :type), "in_app")

  defp field(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
