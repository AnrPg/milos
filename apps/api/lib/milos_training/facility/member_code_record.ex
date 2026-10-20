defmodule MilosTraining.Facility.MemberCodeRecord do
  @moduledoc """
  A member's persistent personal code at a box that keeps static codes
  (board 10, Q5; ADR-155). The code is `StaticMemberCode.sign/3` of `serial`;
  only the serial is stored. At most one active code per member and box.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @reasons ~w(reset staff mode_rotating)

  schema "facility_member_codes" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :serial, Ecto.UUID
    field :revoked_at, :utc_datetime_usec
    field :revoked_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def reasons, do: @reasons

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :user_id, :serial])
    |> validate_required([:organization_id, :user_id, :serial])
    |> unique_constraint([:organization_id, :user_id],
      name: :facility_member_codes_one_active_index
    )
    |> unique_constraint(:serial)
    |> foreign_key_constraint(:user_id)
  end

  def revoke_changeset(code, reason, revoked_at) when reason in @reasons,
    do: change(code, revoked_at: revoked_at, revoked_reason: reason)
end
