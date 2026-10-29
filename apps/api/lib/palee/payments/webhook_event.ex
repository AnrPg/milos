defmodule Palee.Payments.WebhookEvent do
  @moduledoc """
  A provider notification, kept once per event id so a redelivery is
  recognised (ADR-246). Only identifiers are stored, never the body.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(account_id provider event_id event_type reference status error received_at
             processed_at)a

  schema "payment_webhook_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :account_id, :binary_id
    field :provider, :string
    field :event_id, :string
    field :event_type, :string
    field :reference, :string
    field :status, :string, default: "received"
    field :error, :string
    field :received_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:account_id, :provider, :event_id, :status, :received_at])
    |> unique_constraint([:account_id, :event_id])
  end
end
