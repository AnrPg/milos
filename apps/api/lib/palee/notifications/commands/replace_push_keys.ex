defmodule Palee.Notifications.Commands.ReplacePushKeys do
  @moduledoc """
  Makes a new Web Push key pair (ADR-275), for when the private key may have
  leaked. Every browser subscription was made with the old public key and can
  never be delivered again, so all are removed; each device subscribes again
  by itself the next time its owner opens Palee. Refused while the server's
  `WEB_PUSH_*` keys are in use, since those win anyway.
  """

  alias Palee.Notifications.Domain.VapidKeys
  alias Palee.Notifications.PushConfig
  alias Palee.Notifications.PushKeyStore

  def call(vendor_user_id) do
    if PushConfig.config().source == :server do
      {:error, :push_managed_by_server}
    else
      PushKeyStore.with_user_context(%{user_id: vendor_user_id}, fn ->
        {:ok, _stored} = PushKeyStore.replace_keys(VapidKeys.generate())
        {:ok, %{devices_removed: PushKeyStore.forget_all_devices()}}
      end)
    end
  end
end
