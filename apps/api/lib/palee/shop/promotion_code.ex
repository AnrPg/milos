defmodule Palee.Shop.PromotionCode do
  @moduledoc """
  A promotion code of one product (ADR-190 «Προώθηση»): percent off, or an
  amount off each unit, with an optional window and redemption cap, and the
  club post that announced it. Rules: `Palee.Shop.Domain.PromotionPolicy`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Shop.Domain.PromotionPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable [:discount_percent, :discount_cents, :max_redemptions, :starts_at, :ends_at, :active]

  schema "shop_promotion_codes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :product_id, :binary_id
    field :code, :string
    field :discount_percent, :integer
    field :discount_cents, :integer
    field :max_redemptions, :integer
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :active, :boolean, default: true
    field :post_id, :binary_id
    field :created_by_id, :binary_id
    field :redemptions, :integer, virtual: true, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:product_id, :code, :post_id, :created_by_id | @editable])
    |> update_change(:code, &PromotionPolicy.normalize_code/1)
    |> validate_required([:product_id, :code])
    |> validate_code()
  end

  def update_changeset(code, attrs) do
    code
    |> cast(attrs, [:post_id | @editable])
    |> validate_code()
  end

  defp validate_code(changeset) do
    changeset
    |> validate_format(:code, PromotionPolicy.code_format(),
      message: "use 3 to 32 letters, digits, - or _"
    )
    |> validate_number(:discount_percent, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:discount_cents, greater_than: 0)
    |> validate_number(:max_redemptions, greater_than: 0)
    |> validate_one_discount()
    |> validate_window()
    |> unique_constraint(:code, name: :shop_promotion_codes_organization_code_index)
    |> check_constraint(:discount_percent, name: :shop_promotion_codes_discount_check)
    |> check_constraint(:code, name: :shop_promotion_codes_code_check)
    |> check_constraint(:ends_at, name: :shop_promotion_codes_window_check)
    |> foreign_key_constraint(:product_id, name: :shop_promotion_codes_product_fkey)
    |> foreign_key_constraint(:post_id, name: :shop_promotion_codes_post_fkey)
  end

  defp validate_one_discount(changeset) do
    case {get_field(changeset, :discount_percent), get_field(changeset, :discount_cents)} do
      {nil, nil} ->
        add_error(changeset, :discount_percent, "give a percent or an amount")

      {p, c} when not is_nil(p) and not is_nil(c) ->
        add_error(changeset, :discount_cents, "give only one discount")

      _one ->
        changeset
    end
  end

  defp validate_window(changeset) do
    with %DateTime{} = starts <- get_field(changeset, :starts_at),
         %DateTime{} = ends <- get_field(changeset, :ends_at),
         false <- DateTime.compare(starts, ends) == :lt do
      add_error(changeset, :ends_at, "must be after the start")
    else
      _ok -> changeset
    end
  end
end
