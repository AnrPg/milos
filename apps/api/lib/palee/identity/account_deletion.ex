defmodule Palee.Identity.AccountDeletion do
  @moduledoc """
  ADR-211: a login's open deletion request, for one profile (`scope:
  :profile`, `user_id` set) or for the login and all its profiles (`scope:
  :login`). `awaiting_confirmation` until the emailed link is opened, then
  `scheduled` until `scheduled_for` (the end of the 7-day grace).
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "account_deletions" do
    field :login_id, :binary_id
    field :user_id, :binary_id
    field :scope, Ecto.Enum, values: [:profile, :login]
    field :status, Ecto.Enum, values: [:awaiting_confirmation, :scheduled]
    field :confirmed_at, :utc_datetime_usec
    field :scheduled_for, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
