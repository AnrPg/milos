defmodule Palee.Identity.RecoveryCode do
  @moduledoc "ADR-187: one hashed one-time recovery code of a login."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "login_recovery_codes" do
    field :login_id, :binary_id
    field :code_hash, :binary, redact: true
    field :used_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end
end
