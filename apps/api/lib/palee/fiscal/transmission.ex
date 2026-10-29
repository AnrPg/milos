defmodule Palee.Fiscal.Transmission do
  @moduledoc "The outbox row reporting one fiscal document to its authority (ADR-243)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(document_id authority status attempts next_attempt_at claimed_at environment mark
             uid authentication_code qr_url accepted_at last_error_code last_error_message)a

  schema "fiscal_transmissions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :document_id, :binary_id
    field :authority, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :environment, :string
    field :mark, :string
    field :uid, :string
    field :authentication_code, :string
    field :qr_url, :string
    field :accepted_at, :utc_datetime_usec
    field :last_error_code, :string
    field :last_error_message, :string

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields

  def changeset(transmission, attrs) do
    transmission
    |> cast(attrs, @fields)
    |> validate_required([:document_id, :authority, :status])
    |> unique_constraint([:document_id, :authority])
  end
end
