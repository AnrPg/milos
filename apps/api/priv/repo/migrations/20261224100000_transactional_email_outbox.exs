defmodule Palee.Repo.Migrations.TransactionalEmailOutbox do
  @moduledoc """
  ADR-203: the transactional email outbox and its primitives.

  - `email_messages`: one row per email Palee sends. The row and its
    `DeliverEmailJob` are inserted in one transaction; the rendered body is
    stored encrypted (`DataCipher`) and cleared once the email is sent. The
    `idempotency_key` makes a retried request enqueue nothing twice.
  - `email_link_tokens`: single-use links mailed to a person (verify email,
    change email, reset password, ...). Only the token's SHA-256 is stored.
  - `email_suppressions`: addresses Palee must not mail again (a hard
    bounce, a complaint, a manual block), by `InvitationEmail.digest/1`.

  Platform tables, like ADR-187's password recovery tables: written by the
  system (requests and the email worker, which runs with no session scope),
  never read by a tenant session, so they carry no RLS. `email_messages`
  is classified as platform-administered in the tenancy audit.
  """
  use Ecto.Migration

  def change do
    create table(:email_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :to_address, :string, null: false
      add :login_id, references(:logins, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)
      add :locale, :string, null: false, default: "en"
      add :category, :string, null: false
      add :subject, :text, null: false
      add :encrypted_body, :binary
      add :status, :string, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :message_id, :string, null: false
      add :idempotency_key, :string
      add :scheduled_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:email_messages, [:idempotency_key])
    create unique_index(:email_messages, [:message_id])
    create index(:email_messages, [:to_address, :kind, :inserted_at])
    create index(:email_messages, [:sent_at], where: "sent_at IS NOT NULL")
    create index(:email_messages, [:organization_id], where: "organization_id IS NOT NULL")
    create index(:email_messages, [:login_id], where: "login_id IS NOT NULL")
    create index(:email_messages, [:user_id], where: "user_id IS NOT NULL")

    create constraint(:email_messages, :email_messages_category_check,
             check: "category IN ('security', 'account', 'transactional')"
           )

    create constraint(:email_messages, :email_messages_status_check,
             check: "status IN ('queued', 'sent', 'failed', 'suppressed', 'deferred')"
           )

    create table(:email_link_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :purpose, :string, null: false
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :target_email, :string
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:email_link_tokens, [:token_hash])
    create index(:email_link_tokens, [:login_id, :purpose])

    create constraint(:email_link_tokens, :email_link_tokens_purpose_check,
             check: "purpose ~ '^[a-z][a-z_]{1,47}$'"
           )

    create table(:email_suppressions, primary_key: false) do
      add :address_digest, :binary, primary_key: true
      add :reason, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create constraint(:email_suppressions, :email_suppressions_reason_check,
             check: "reason IN ('bounce', 'complaint', 'manual')"
           )
  end
end
