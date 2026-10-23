defmodule Palee.Identity.PasswordResetRequest do
  @moduledoc "ADR-187: a person's open request to have their password reset."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "password_reset_requests" do
    field :status, :string, default: "open"
    field :claimed_at, :utc_datetime_usec
    field :link_token_hash, :binary, redact: true
    field :link_expires_at, :utc_datetime_usec
    field :link_issued_at, :utc_datetime_usec

    belongs_to :login, Palee.Identity.Login
    belongs_to :user, Palee.Identity.User
    belongs_to :claimed_by, Palee.Identity.User, foreign_key: :claimed_by_user_id
    belongs_to :link_issued_by, Palee.Identity.User, foreign_key: :link_issued_by_user_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:login_id, :user_id])
    |> validate_required([:login_id, :user_id])
    |> unique_constraint(:login_id)
  end

  def update_changeset(request, params) do
    request
    |> cast(params, [
      :status,
      :claimed_by_user_id,
      :claimed_at,
      :link_token_hash,
      :link_expires_at,
      :link_issued_by_user_id,
      :link_issued_at
    ])
    |> validate_inclusion(:status, ["open", "link_issued"])
  end
end
