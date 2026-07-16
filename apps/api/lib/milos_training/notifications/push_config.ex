defmodule MilosTraining.Notifications.PushConfig do
  alias MilosTraining.Notifications.NotificationStore

  def enabled? do
    config()
    |> Map.take([:vapid_public_key, :vapid_private_key, :vapid_subject])
    |> Enum.all?(fn {_key, value} -> is_binary(value) and value != "" end)
  end

  def public_key do
    config()[:vapid_public_key]
  end

  def config do
    persisted_config()
    |> fallback_to_application_env()
  end

  def apply_to_web_push_elixir do
    current = config()

    Application.put_env(:web_push_elixir, :vapid_public_key, current[:vapid_public_key])
    Application.put_env(:web_push_elixir, :vapid_private_key, current[:vapid_private_key])
    Application.put_env(:web_push_elixir, :vapid_subject, current[:vapid_subject])

    :ok
  end

  defp persisted_config do
    case NotificationStore.get_push_delivery_config() do
      %{} = settings ->
        settings
        |> Enum.into(%{})
        |> Map.take([:vapid_public_key, :vapid_private_key, :vapid_subject])

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp fallback_to_application_env(%{} = config) do
    legacy_config =
      Application.get_env(:web_push_elixir, :vapid_config, [])
      |> Enum.into(%{})

    %{
      vapid_public_key:
        present_or_nil(config[:vapid_public_key]) ||
          present_or_nil(Application.get_env(:web_push_elixir, :vapid_public_key)) ||
          present_or_nil(legacy_config[:vapid_public_key]),
      vapid_private_key:
        present_or_nil(config[:vapid_private_key]) ||
          present_or_nil(Application.get_env(:web_push_elixir, :vapid_private_key)) ||
          present_or_nil(legacy_config[:vapid_private_key]),
      vapid_subject:
        present_or_nil(config[:vapid_subject]) ||
          present_or_nil(Application.get_env(:web_push_elixir, :vapid_subject)) ||
          present_or_nil(legacy_config[:vapid_subject])
    }
  end

  defp present_or_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present_or_nil(_value), do: nil
end
