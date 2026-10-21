defmodule MilosTraining.Application.RegisterNativePushToken do
  @moduledoc "Registers a store app install for push (ADR-171)."

  alias MilosTraining.Notifications

  def call(user_id, params), do: Notifications.register_native_push_token(user_id, params)
end
