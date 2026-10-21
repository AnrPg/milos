defmodule Palee.Pantheon.PRShareGrant do
  @moduledoc """
  An explicit, user-owned grant letting `grantee_user_id` read every PR of
  `user_id` (ADR-055 personal grant, ADR-129). Grants are global personal data:
  they carry no organization and are revoked by stamping `revoked_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_pr_share_grants" do
    field(:user_id, :binary_id)
    field(:grantee_user_id, :binary_id)
    field(:revoked_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:user_id, :grantee_user_id])
    |> validate_required([:user_id, :grantee_user_id])
    |> check_constraint(:grantee_user_id,
      name: :user_pr_share_grants_not_self,
      message: "cannot be the owner"
    )
    |> unique_constraint([:user_id, :grantee_user_id],
      name: :user_pr_share_grants_active_index,
      message: "already has access"
    )
    |> foreign_key_constraint(:grantee_user_id)
  end

  def revoke_changeset(%__MODULE__{} = grant, revoked_at) do
    change(grant, revoked_at: revoked_at)
  end
end
