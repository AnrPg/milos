defmodule MilosTraining.Repo.Migrations.AlignInvitedAccountRolesAndSettings do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO organization_settings (
      id,
      organization_id,
      timezone,
      default_locale,
      invitation_lifetime_seconds,
      brand_name,
      settings,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      organizations.id,
      'UTC',
      'en',
      604800,
      organizations.name,
      '{}'::jsonb,
      timezone('utc', now()),
      timezone('utc', now())
    FROM organizations
    WHERE NOT EXISTS (
      SELECT 1
      FROM organization_settings
      WHERE organization_settings.organization_id = organizations.id
    )
    """)

    execute("""
    WITH ranked_memberships AS (
      SELECT
        organization_memberships.user_id,
        CASE
          WHEN bool_or(organization_memberships.role IN ('owner', 'admin', 'coach')) THEN 'admin'
          WHEN bool_or(organization_memberships.role = 'athlete') THEN 'athlete'
          ELSE 'member'
        END AS account_role
      FROM organization_memberships
      WHERE organization_memberships.status = 'active'
      GROUP BY organization_memberships.user_id
    )
    UPDATE users
    SET role = ranked_memberships.account_role,
        updated_at = timezone('utc', now())
    FROM ranked_memberships
    WHERE users.id = ranked_memberships.user_id
      AND users.role IS DISTINCT FROM ranked_memberships.account_role
      AND NOT EXISTS (
        SELECT 1
        FROM vendors
        WHERE vendors.user_id = users.id
          AND vendors.status = 'active'
      )
    """)
  end

  def down do
    :ok
  end
end
