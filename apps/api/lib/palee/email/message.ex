defmodule Palee.Email.Message do
  @moduledoc """
  One outbox row (ADR-203): an email Palee has accepted to send. The body
  is rendered at enqueue time and kept encrypted (`encrypted_body`) until
  the email is sent, then cleared; the subject stays for the status views.

  `status`: `queued` (waiting for its job), `deferred` (over the daily
  budget, snoozed to the next UTC day), `sent`, `failed` (gave up after the
  last attempt) or `suppressed` (the address is on the suppression list).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(queued sent failed suppressed deferred)
  @categories ~w(security account transactional)

  schema "email_messages" do
    field :kind, :string
    field :to_address, :string
    field :login_id, :binary_id
    field :user_id, :binary_id
    field :organization_id, :binary_id
    field :locale, :string, default: "en"
    field :category, :string
    field :subject, :string
    field :encrypted_body, :binary, redact: true
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :message_id, :string
    field :idempotency_key, :string
    field :scheduled_at, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec

    # Decrypted bodies, filled only by test helpers (`Palee.EmailCase`).
    field :text, :string, virtual: true, redact: true
    field :html, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The statuses a message can be in."
  def statuses, do: @statuses

  @fields ~w(kind to_address login_id user_id organization_id locale category subject
             encrypted_body status message_id idempotency_key scheduled_at)a

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(~w(kind to_address locale category subject encrypted_body status
                            message_id)a)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:category, @categories)
    |> unique_constraint(:idempotency_key)
  end
end
