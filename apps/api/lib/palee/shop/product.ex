defmodule Palee.Shop.Product do
  @moduledoc "A product the business sells, with its variants (ADR-190)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Shop.Domain.ProductPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable [
    :title,
    :description,
    :category,
    :media_ids,
    :options,
    :visibility,
    :sell_in_app,
    :sell_at_desk,
    :member_discount_applies,
    :per_person_limit,
    :all_locations,
    :location_ids,
    :position
  ]

  schema "shop_products" do
    field :organization_id, :binary_id, read_after_writes: true
    field :title, :string
    field :description, :string
    field :category, :string
    field :media_ids, {:array, :binary_id}, default: []
    field :options, :map, default: %{}
    field :status, Ecto.Enum, values: ProductPolicy.statuses(), default: :draft
    field :visibility, Ecto.Enum, values: ProductPolicy.visibilities(), default: :members_only
    field :sell_in_app, :boolean, default: true
    field :sell_at_desk, :boolean, default: true
    field :member_discount_applies, :boolean, default: false
    field :per_person_limit, :integer
    field :all_locations, :boolean, default: true
    field :location_ids, {:array, :binary_id}, default: []
    field :position, :integer, default: 0
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def editable, do: @editable

  def changeset(product \\ %__MODULE__{}, attrs) do
    product
    |> cast(attrs, [:status, :published_at, :archived_at, :created_by_id | @editable])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :status, :visibility])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:description, max: 8000)
    |> validate_length(:category, max: 80)
    |> validate_length(:media_ids, max: 12)
    |> validate_length(:location_ids, max: 200)
    |> validate_number(:per_person_limit, greater_than: 0)
    |> validate_change(:options, fn :options, options ->
      case ProductPolicy.normalize_options(options) do
        {:ok, _options} -> []
        {:error, reason} -> [options: Atom.to_string(reason)]
      end
    end)
    |> check_constraint(:location_ids, name: :shop_products_location_scope_check)
  end
end
