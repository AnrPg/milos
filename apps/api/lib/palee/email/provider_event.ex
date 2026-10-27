defmodule Palee.Email.ProviderEvent do
  @moduledoc """
  One event the mail provider reported about a sent email (ADR-212), keyed
  by a digest of the event itself so a webhook the provider retries is
  applied once. Only the address's digest is kept.
  """

  use Ecto.Schema

  @primary_key {:event_digest, :binary, autogenerate: false}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "email_provider_events" do
    field :provider, :string
    field :event, :string
    field :email_message_id, :binary_id
    field :address_digest, :binary
    field :reason, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
