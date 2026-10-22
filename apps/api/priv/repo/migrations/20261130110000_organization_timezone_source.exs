defmodule Palee.Repo.Migrations.OrganizationTimezoneSource do
  @moduledoc """
  ADR-176: how a gym's time zone was learnt. A zone other than the untouched
  UTC default was set on purpose (by the vendor or at sign-up) and counts as
  confirmed; a UTC one is treated as never set, so onboarding asks for it and
  a staff device may suggest a guess meanwhile.
  """

  use Ecto.Migration

  def up do
    alter table(:organization_settings) do
      add :timezone_source, :string
    end

    create constraint(:organization_settings, :organization_settings_timezone_source_check,
             check: "timezone_source IS NULL OR timezone_source IN ('confirmed', 'inferred')"
           )

    execute("""
    UPDATE organization_settings SET timezone_source = 'confirmed'
    WHERE timezone NOT IN ('UTC', 'Etc/UTC', 'Etc/GMT', 'GMT')
    """)
  end

  def down do
    drop constraint(:organization_settings, :organization_settings_timezone_source_check)

    alter table(:organization_settings) do
      remove :timezone_source
    end
  end
end
