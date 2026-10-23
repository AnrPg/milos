defmodule Palee.Shop.StockAlert do
  @moduledoc """
  «Ειδοποίησέ με» (ADR-190): a member asks to hear when a sold-out variant is
  back. `notified_at` is set once they were told; asking again clears it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shop_stock_alerts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :variant_id, :binary_id
    field :user_id, :binary_id
    field :notified_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(alert \\ %__MODULE__{}, attrs) do
    alert
    |> cast(attrs, [:variant_id, :user_id, :notified_at])
    |> validate_required([:variant_id, :user_id])
    |> unique_constraint([:variant_id, :user_id], name: :shop_stock_alerts_variant_user_index)
    |> foreign_key_constraint(:variant_id, name: :shop_stock_alerts_variant_fkey)
    |> foreign_key_constraint(:user_id)
  end
end
