defmodule MilosTraining.Repo.Migrations.AllowNullOrganizationOnNotificationClickEvents do
  use Ecto.Migration

  # MilosTraining.Application.MarkNotificationClicked reads the notification's
  # own organization_id explicitly (F-28: the notification inbox spans every
  # org a member belongs to, so a click on a cross-org/organization-less
  # notification is a legitimate, expected case - not an error). Before the
  # legacy-default columns were dropped (20260808154000), a null value here
  # was silently coerced to the legacy org by the column DEFAULT; now it
  # fails NOT NULL. Relax the constraint to match what the application has
  # always intended to allow.
  def up do
    execute("ALTER TABLE notification_click_events ALTER COLUMN organization_id DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE notification_click_events ALTER COLUMN organization_id SET NOT NULL")
  end
end
