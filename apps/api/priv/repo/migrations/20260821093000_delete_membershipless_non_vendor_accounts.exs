defmodule MilosTraining.Repo.Migrations.DeleteMembershiplessNonVendorAccounts do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE
      candidate_id uuid;
    BEGIN
      FOR candidate_id IN
        SELECT users.id
        FROM users
        WHERE NOT EXISTS (
          SELECT 1
          FROM organization_memberships
          WHERE organization_memberships.user_id = users.id
        )
        AND NOT EXISTS (
          SELECT 1
          FROM vendors
          WHERE vendors.user_id = users.id
            AND vendors.status = 'active'
        )
      LOOP
        BEGIN
          DELETE FROM users
          WHERE users.id = candidate_id;
        EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
          NULL;
        END;
      END LOOP;
    END
    $$;
    """)
  end

  def down do
    :ok
  end
end
