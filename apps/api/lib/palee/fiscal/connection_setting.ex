defmodule Palee.Fiscal.ConnectionSetting do
  @moduledoc """
  Who manages an organization's fiscal connections (ADR-273): the box's
  owner (`owner`, the default when there is no row) or the Palee team
  (`palee`), chosen per box from the vendor console. When the Palee team
  manages them, the box's staff see the connections but cannot change
  them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @managers ~w(owner palee)

  def managers, do: @managers

  schema "fiscal_connection_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :managed_by, :string, default: "owner"
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:managed_by, :updated_by_id])
    |> validate_required([:managed_by])
    |> validate_inclusion(:managed_by, @managers)
    |> unique_constraint(:organization_id)
    |> check_constraint(:managed_by, name: :fiscal_connection_settings_managed_by_check)
  end
end
