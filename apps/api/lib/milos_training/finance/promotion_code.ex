defmodule MilosTraining.Finance.PromotionCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promotion_codes" do
    field :promotion_campaign_id, :binary_id
    field :code, :string
    field :discount_type, :string
    field :discount_value, :integer, default: 0
    field :max_redemptions, :integer
    field :active, :boolean, default: true
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(promotion_code \\ %__MODULE__{}, params) do
    promotion_code
    |> cast(normalize_params(params), [
      :promotion_campaign_id,
      :code,
      :discount_type,
      :discount_value,
      :max_redemptions,
      :active,
      :params
    ])
    |> update_change(:code, &normalize_code/1)
    |> validate_required([:promotion_campaign_id, :code, :discount_type, :discount_value, :active])
    |> validate_inclusion(:discount_type, ["percent", "fixed_amount", "free_period", "manual"])
    |> validate_number(:discount_value, greater_than_or_equal_to: 0)
    |> validate_percent_limit()
    |> validate_number(:max_redemptions, greater_than: 0)
    |> unique_constraint(:code)
    |> foreign_key_constraint(:promotion_campaign_id)
  end

  defp normalize_code(nil), do: nil

  defp normalize_code(code) do
    code
    |> String.trim()
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9_-]+/, "-")
    |> String.trim("-")
  end

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {key, "fixed"} when key in [:discount_type, "discount_type"] -> {key, "fixed_amount"}
      pair -> pair
    end)
  end

  defp validate_percent_limit(changeset) do
    if get_field(changeset, :discount_type) == "percent" do
      validate_number(changeset, :discount_value, less_than_or_equal_to: 100)
    else
      changeset
    end
  end
end
