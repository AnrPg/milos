defmodule MilosTraining.Notifications.Commands.DeleteNativePushToken do
  @moduledoc "Forgets a store app install's push token (sign-out, or the provider said it is gone)."

  alias MilosTraining.Notifications.NativePushTokenStore

  def call(user_id, token), do: NativePushTokenStore.delete_native_push_token(user_id, token)

  def by_id(user_id, id), do: NativePushTokenStore.delete_native_push_token_by_id(user_id, id)
end
