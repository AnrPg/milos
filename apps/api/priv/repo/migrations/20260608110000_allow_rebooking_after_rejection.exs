defmodule MilosTraining.Repo.Migrations.AllowRebookingAfterRejection do
  use Ecto.Migration

  def change do
    drop_if_exists index(:bookings, [:scheduled_class_id, :user_id],
                     name: :bookings_slot_user_index
                   )

    create unique_index(:bookings, [:scheduled_class_id, :user_id],
             where: "status IN ('pending', 'approved')",
             name: :bookings_slot_user_index
           )
  end
end
