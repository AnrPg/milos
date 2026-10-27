defmodule Palee.Identity.LoginDevice do
  @moduledoc "ADR-208: a device a login has signed in from (only its hash is kept)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "login_devices" do
    field :login_id, :binary_id
    field :device_hash, :binary, redact: true
    field :client, :string
    field :platform, :string
    field :sign_ins, :integer, default: 0
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
  end
end
