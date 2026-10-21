defmodule MilosTraining.Application.DeleteNativePushToken do
  @moduledoc "Stops push to a store app install, e.g. on sign-out (ADR-171)."

  alias MilosTraining.Notifications

  def call(user_id, token) when is_binary(token),
    do: Notifications.delete_native_push_token(user_id, token)
end
