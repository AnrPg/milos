defmodule Palee.Repo.Migrations.InvitationsSentByEmail do
  @moduledoc """
  ADR-209: a box sends its client and staff invitations from the app.

  - `intended_email_encrypted` is the invited address, encrypted with
    `DataCipher` (`EncryptedBinary`), so "Resend" can mail it again and the
    pending list can show whom it went to. `intended_email_digest` stays the
    one the redemption compares against.
  - `email_locale` is the language the email was written in; a resend keeps
    it.
  - `emailed_at` is set when the token went only into the email: the inviter
    never saw it, so whoever opens the link proves they read that inbox.
  - `email_verification_required` marks an email-bound invitation issued by
    a business: it is redeemed only by a login whose matching address is
    verified, or through the emailed link. Platform owner invitations keep
    the older rule (the address must match) unless they set it.
  - The two partial indexes count the invitations emailed in the last 24 h
    per business and per inviter (the daily caps).

  The table keeps its RLS policies; new columns need no policy change.
  """

  use Ecto.Migration

  def change do
    alter table(:registration_invitations) do
      add :intended_email_encrypted, :binary
      add :email_locale, :string
      add :emailed_at, :utc_datetime_usec
      add :email_verification_required, :boolean, null: false, default: false
    end

    create index(:registration_invitations, [:organization_id, :emailed_at],
             where: "emailed_at IS NOT NULL",
             name: :registration_invitations_emailed_per_org_index
           )

    create index(:registration_invitations, [:issued_by_user_id, :emailed_at],
             where: "emailed_at IS NOT NULL",
             name: :registration_invitations_emailed_per_inviter_index
           )
  end
end
