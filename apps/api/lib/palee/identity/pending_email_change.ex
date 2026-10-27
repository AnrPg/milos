defmodule Palee.Identity.PendingEmailChange do
  @moduledoc """
  ADR-207: a login's one pending email change. The login keeps its current
  address until the link sent to `new_email` is opened before `expires_at`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "login_email_changes" do
    field :new_email, :string
    field :requested_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :login, Palee.Identity.Login

    timestamps(type: :utc_datetime_usec)
  end
end
