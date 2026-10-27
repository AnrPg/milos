defmodule Palee.Repo.Migrations.PasswordResetByEmail do
  use Ecto.Migration

  # ADR-206: a reset link is emailed automatically to a verified address; the
  # handler requests of ADR-187 stay as the fallback.
  #
  # - `password_reset_requests.requester_key`: an HMAC of the requesting IP
  #   (never the IP itself), so one client can file only a few handler
  #   requests a day and cannot flood the handlers' inbox.
  # - The vendor's security log gains `link_emailed` (the automatic email
  #   was queued) and `throttled` (a request over the limits; nothing sent).

  @old_events ~w(requested claimed released link_issued completed rejected dismissed recovery_code_used)
  @new_events @old_events ++ ~w(link_emailed throttled)

  def up do
    alter table(:password_reset_requests) do
      add :requester_key, :binary
    end

    create index(:password_reset_requests, [:requester_key, :inserted_at],
             where: "requester_key IS NOT NULL"
           )

    replace_events(@new_events)
  end

  def down do
    execute("DELETE FROM password_reset_log WHERE event NOT IN (#{in_list(@old_events)})")

    replace_events(@old_events)
    drop index(:password_reset_requests, [:requester_key, :inserted_at])

    alter table(:password_reset_requests) do
      remove :requester_key
    end
  end

  defp replace_events(events) do
    drop constraint(:password_reset_log, :password_reset_log_event)

    create constraint(:password_reset_log, :password_reset_log_event,
             check: "event IN (#{in_list(events)})"
           )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
