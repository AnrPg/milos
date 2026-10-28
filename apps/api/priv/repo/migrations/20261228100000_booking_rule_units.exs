defmodule Palee.Repo.Migrations.BookingRuleUnits do
  use Ecto.Migration

  # ADR-222: a booking request may wait for approval without a limit (NULL =
  # until the class starts), and the gym's late-cancellation cutoff is stored
  # in minutes so staff can set hours and minutes.

  def up do
    alter table(:scheduling_settings) do
      modify :default_booking_timeout_minutes, :integer, null: true, default: 60
      add :default_cancellation_cutoff_minutes, :integer
    end

    execute """
    UPDATE scheduling_settings
    SET default_cancellation_cutoff_minutes = default_cancellation_cutoff_hours * 60
    WHERE default_cancellation_cutoff_hours IS NOT NULL
    """

    alter table(:scheduling_settings) do
      remove :default_cancellation_cutoff_hours
    end

    create constraint(:scheduling_settings, :scheduling_settings_cancellation_cutoff_minutes,
             check: "default_cancellation_cutoff_minutes BETWEEN 0 AND 10080"
           )

    alter table(:scheduled_classes) do
      modify :booking_timeout_minutes, :integer, null: true, default: 60
    end

    alter table(:class_series) do
      modify :booking_timeout_minutes, :integer, null: true, default: 60
    end
  end

  def down do
    execute "UPDATE scheduled_classes SET booking_timeout_minutes = 60 WHERE booking_timeout_minutes IS NULL"

    execute "UPDATE class_series SET booking_timeout_minutes = 60 WHERE booking_timeout_minutes IS NULL"

    execute """
    UPDATE scheduling_settings SET default_booking_timeout_minutes = 60
    WHERE default_booking_timeout_minutes IS NULL
    """

    alter table(:class_series) do
      modify :booking_timeout_minutes, :integer, null: false, default: 60
    end

    alter table(:scheduled_classes) do
      modify :booking_timeout_minutes, :integer, null: false, default: 60
    end

    drop constraint(:scheduling_settings, :scheduling_settings_cancellation_cutoff_minutes)

    alter table(:scheduling_settings) do
      add :default_cancellation_cutoff_hours, :integer
    end

    # Rounds up so a restored cutoff never becomes more lenient.
    execute """
    UPDATE scheduling_settings
    SET default_cancellation_cutoff_hours = CEIL(default_cancellation_cutoff_minutes / 60.0)::integer
    WHERE default_cancellation_cutoff_minutes IS NOT NULL
    """

    alter table(:scheduling_settings) do
      remove :default_cancellation_cutoff_minutes
      modify :default_booking_timeout_minutes, :integer, null: false, default: 60
    end
  end
end
