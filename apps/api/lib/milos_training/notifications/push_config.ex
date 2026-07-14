defmodule MilosTraining.Notifications.PushConfig do
  def enabled? do
    config()
    |> Map.take([:vapid_public_key, :vapid_private_key, :vapid_subject])
    |> Enum.all?(fn {_key, value} -> is_binary(value) and value != "" end)
  end

  def public_key do
    config()[:vapid_public_key]
  end

  def config do
    Application.get_env(:web_push_elixir, :vapid_config, [])
    |> Enum.into(%{})
  end
end
