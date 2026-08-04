defmodule MilosTraining.Repo.Migrations.PromoteLegacyMilosTenantBranding do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE organizations
    SET name = 'Milos Training',
        updated_at = timezone('utc', now())
    WHERE slug = 'legacy-milos-training'
      AND name = 'Legacy Milos Training'
    """)

    execute("""
    UPDATE organization_settings
    SET brand_name = 'Milos Training',
        updated_at = timezone('utc', now())
    FROM organizations
    WHERE organization_settings.organization_id = organizations.id
      AND organizations.slug = 'legacy-milos-training'
      AND (
        organization_settings.brand_name IS NULL
        OR organization_settings.brand_name = 'Legacy Milos Training'
      )
    """)
  end

  def down do
    execute("""
    UPDATE organization_settings
    SET brand_name = NULL,
        updated_at = timezone('utc', now())
    FROM organizations
    WHERE organization_settings.organization_id = organizations.id
      AND organizations.slug = 'legacy-milos-training'
      AND organization_settings.brand_name = 'Milos Training'
    """)

    execute("""
    UPDATE organizations
    SET name = 'Legacy Milos Training',
        updated_at = timezone('utc', now())
    WHERE slug = 'legacy-milos-training'
      AND name = 'Milos Training'
    """)
  end
end
