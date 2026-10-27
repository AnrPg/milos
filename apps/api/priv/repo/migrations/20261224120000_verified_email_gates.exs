defmodule Palee.Repo.Migrations.VerifiedEmailGates do
  @moduledoc """
  ADR-205: features that trust an account's email need it verified.

  - `membership_package_subscriptions.corporate_enrolled_via`: how a
    corporate seat was taken (`code` | `email_domain` | nil for a seat an
    admin added or one older than this column). A seat taken by the email
    domain ends when the login's email leaves that domain.
  - `business_activation_links.email`: the verified address the vendor's
    link was issued for and emailed to. Opening the link proves the
    account reads that address.

  Both are plain columns on tables whose RLS policies and grants already
  cover every column.
  """

  use Ecto.Migration

  def change do
    alter table(:membership_package_subscriptions) do
      add :corporate_enrolled_via, :text
    end

    create constraint(:membership_package_subscriptions, :corporate_enrolled_via_check,
             check:
               "corporate_enrolled_via IS NULL OR corporate_enrolled_via IN ('code', 'email_domain')"
           )

    alter table(:business_activation_links) do
      add :email, :text
    end
  end
end
