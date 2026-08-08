defmodule MilosTraining.Repo.Migrations.AddSchedulingTenantHotPathIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:scheduled_classes, [:organization_id, :scheduled_at],
                           name: :scheduled_classes_org_scheduled_at_index
                         )

    create_if_not_exists index(
                           :scheduled_classes,
                           [:organization_id, :class_type_id, :scheduled_at],
                           name: :scheduled_classes_org_class_type_scheduled_at_index
                         )

    create_if_not_exists index(:bookings, [:organization_id, :status, :inserted_at],
                           name: :bookings_org_status_inserted_at_index
                         )
  end
end
