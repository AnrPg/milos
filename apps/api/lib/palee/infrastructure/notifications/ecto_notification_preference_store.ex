defmodule Palee.Infrastructure.Notifications.EctoNotificationPreferenceStore do
  @moduledoc "Ecto adapter of notification choices (ADR-199); row security admits only the owner's rows."

  @behaviour Palee.Notifications.Ports.NotificationPreferenceStore

  import Ecto.Query

  alias Palee.Notifications.NotificationPreference
  alias Palee.Repo

  @impl true
  def list(%{user_id: user_id}) do
    NotificationPreference
    |> where([p], p.user_id == ^user_id)
    |> select([p], %{category: p.category, channel: p.channel, enabled: p.enabled})
    |> Repo.all()
  end

  @impl true
  def put(%{user_id: user_id}, category, pairs, now) do
    rows =
      Enum.map(pairs, fn {channel, enabled} ->
        %{
          user_id: user_id,
          category: category,
          channel: channel,
          enabled: enabled,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(NotificationPreference, rows,
      on_conflict: {:replace, [:enabled, :updated_at]},
      conflict_target: [:user_id, :category, :channel]
    )

    :ok
  end
end
