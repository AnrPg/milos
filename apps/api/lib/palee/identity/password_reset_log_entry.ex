defmodule Palee.Identity.PasswordResetLogEntry do
  @moduledoc "ADR-187: one line of the password reset security log (vendor only)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @events ~w(requested claimed released link_issued completed rejected dismissed recovery_code_used)

  schema "password_reset_log" do
    field :login_id, :binary_id
    field :user_id, :binary_id
    field :handle, :string
    field :handler_user_id, :binary_id
    field :handler_handle, :string
    field :event, :string
    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end

  def events, do: @events
end
