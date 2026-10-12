defmodule MilosTraining.Repo.Migrations.AddBookingOperationIds do
  @moduledoc """
  ADR-110: client operation identities for offline-replayable booking commands.

  `client_operation_id` dedupes a member's booking request replay; it is unique
  per tenant and requesting user (rows without a key are unconstrained).
  `resolution_operation_id` records which admin command resolved a booking so
  a replay of that exact command converges instead of reporting a conflict.
  Both columns are additive and nullable on the already tenant-scoped,
  RLS-forced `bookings` table.
  """
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :client_operation_id, :uuid
      add :resolution_operation_id, :uuid
    end

    create unique_index(:bookings, [:organization_id, :user_id, :client_operation_id],
             where: "client_operation_id IS NOT NULL",
             name: :bookings_client_operation_index
           )
  end
end
