defmodule Palee.Notifications.Queries.GetPlatformPushStatus do
  @moduledoc """
  What the platform console shows about browser alerts (ADR-275): whether they
  work, whose keys sign them (the server's env or Palee's own pair), the
  contact and where it comes from, how many devices allow alerts and when one
  was last delivered. Never a key.
  """

  alias Palee.Notifications.PushConfig
  alias Palee.Notifications.PushKeyStore

  def call(vendor_user_id) do
    config = PushConfig.config()

    stats =
      PushKeyStore.with_user_context(%{user_id: vendor_user_id}, &PushKeyStore.device_stats/0)

    %{
      enabled: PushConfig.ready?(config),
      source: Atom.to_string(config.source),
      vapid_subject: config.vapid_subject,
      subject_source: subject_source(),
      keys_created_at: config.keys_created_at,
      device_count: stats.device_count,
      last_sent_at: stats.last_sent_at
    }
  end

  defp subject_source do
    server = Application.get_env(:palee, :web_push_server_keys, [])[:subject]

    cond do
      present?(server) -> "server"
      present?(PushKeyStore.get().vapid_subject) -> "palee"
      true -> "default"
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
