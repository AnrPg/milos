defmodule Palee.Notifications.Commands.SaveNativePushToken do
  @moduledoc "Registers (or refreshes) a store app install's push token (ADR-171)."

  alias Palee.Notifications.NativePushTokenStore

  def call(params), do: NativePushTokenStore.save_native_push_token(params)
end
