defmodule MilosTraining.Repo.Migrations.WidgetsGeofenceAndNfc do
  @moduledoc """
  ADR-173 (P3-M11): home-screen widgets, the geofenced check-in reminder and
  NFC door tags.

  - `facility_locations` gets an NFC tag like its printed poster (ADR-155
    §5): a static code derived from `nfc_secret` (rotated on demand) and the
    application secret, switched on per location. A tag tap only checks in a
    booking already in its window (method `door_nfc`).
  - `facility_check_in_settings.geofence_reminder`: whether the box's members
    may get the «Έφτασες» reminder near a location (default on). Tapping it
    also only checks in a booking in its window (method `geofence`).
  - `widget_tokens`: one row per app install that shows widgets. The widget
    authenticates with a signed token naming the row, so signing out (or a
    new token for the install) revokes it. The person's own rows
    (personal-session RLS, like `native_push_tokens`).
  """

  use Ecto.Migration

  @old_methods ~w(door_qr door_poster member_qr wallet desk_search self)
  @methods @old_methods ++ ~w(door_nfc geofence)

  def up do
    alter table(:facility_locations) do
      add :nfc_enabled, :boolean, null: false, default: false

      add :nfc_secret, :binary,
        null: false,
        default:
          fragment(
            "decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex')"
          )

      add :nfc_secret_rotated_at, :utc_datetime_usec
    end

    alter table(:facility_check_in_settings) do
      add :geofence_reminder, :boolean, null: false, default: true
    end

    replace_method_checks(@methods)

    create table(:widget_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:widget_tokens, :widget_tokens_platform_check,
             check: "platform IN ('ios', 'android')"
           )

    create index(:widget_tokens, [:user_id, :inserted_at])

    execute("""
    CREATE POLICY widget_tokens_owner_policy ON widget_tokens
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE widget_tokens ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE widget_tokens FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:widget_tokens)

    execute(
      "UPDATE facility_check_ins SET method = 'door_poster' WHERE method IN ('door_nfc', 'geofence')"
    )

    execute(
      "UPDATE class_attendance_records SET check_in_method = 'door_poster' " <>
        "WHERE check_in_method IN ('door_nfc', 'geofence')"
    )

    replace_method_checks(@old_methods)

    alter table(:facility_check_in_settings) do
      remove :geofence_reminder
    end

    alter table(:facility_locations) do
      remove :nfc_secret_rotated_at
      remove :nfc_secret
      remove :nfc_enabled
    end
  end

  defp replace_method_checks(methods) do
    drop constraint(:facility_check_ins, :facility_check_ins_method_check)

    create constraint(:facility_check_ins, :facility_check_ins_method_check,
             check: "method IN (#{in_list(methods)})"
           )

    drop constraint(:class_attendance_records, :class_attendance_records_method_check)

    create constraint(:class_attendance_records, :class_attendance_records_method_check,
             check: "check_in_method IS NULL OR check_in_method IN (#{in_list(methods)})"
           )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
