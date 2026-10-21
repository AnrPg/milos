defmodule MilosTraining.Notifications.Queries.ListNativePushTokens do
  @moduledoc "The person's store app installs that receive push (ADR-171)."

  alias MilosTraining.Notifications.NativePushTokenStore

  def call(user_id), do: NativePushTokenStore.list_native_push_tokens(user_id)

  def get(user_id, id), do: NativePushTokenStore.get_native_push_token(user_id, id)
end
