defmodule Palee.Email.LinkToken do
  @moduledoc """
  A single-use email link (ADR-203): only the SHA-256 of the raw token is
  stored. `used_at` is set once, atomically, by `LinkTokens.consume/3`.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "email_link_tokens" do
    field :purpose, :string
    field :login_id, :binary_id
    field :user_id, :binary_id
    field :target_email, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
