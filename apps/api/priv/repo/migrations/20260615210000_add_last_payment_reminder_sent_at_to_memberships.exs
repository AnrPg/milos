defmodule MilosTraining.Repo.Migrations.AddLastPaymentReminderSentAtToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :last_payment_reminder_sent_at, :utc_datetime_usec
    end
  end
end
