defmodule MilosTraining.Application.SavePushSubscription do
  alias MilosTraining.Notifications

  def call(user_id, params) do
    Notifications.save_push_subscription(user_id, params)
  end
end
