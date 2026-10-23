defmodule Palee.Perks.Benefit do
  @moduledoc """
  What a perk gives (ADR-191 §3), a validated document stored on the perk
  version. `schema_version` lets a later shape be read next to this one.

    * `percent` — `percent` 1-100 off;
    * `fixed_amount` — `amount_cents` off, in `currency`;
    * `free_item` — `item` free («shaker»);
    * `buy_x_get_y` — buy `buy_quantity`, get `get_quantity` (of `item`, when named);
    * `free_text` — anything else, in `text`.

  `min_spend_cents` and `max_discount_cents` are optional for every type
  (a cap only means something for a percent); `text` may add a note to any.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @schema_version 1
  @types ~w(percent fixed_amount free_item buy_x_get_y free_text)
  @fields ~w(type percent amount_cents currency item buy_quantity get_quantity text
             min_spend_cents max_discount_cents)a

  @primary_key false
  embedded_schema do
    field :schema_version, :integer, default: @schema_version
    field :type, :string
    field :percent, :integer
    field :amount_cents, :integer
    field :currency, :string, default: "EUR"
    field :item, :string
    field :buy_quantity, :integer
    field :get_quantity, :integer
    field :text, :string
    field :min_spend_cents, :integer
    field :max_discount_cents, :integer
  end

  @type t :: %__MODULE__{}

  def schema_version, do: @schema_version
  def types, do: @types
  def fields, do: @fields

  def changeset(benefit \\ %__MODULE__{}, attrs) do
    benefit
    |> cast(attrs, @fields)
    |> put_change(:schema_version, @schema_version)
    |> update_change(:currency, &upcase/1)
    |> validate_required([:type])
    |> validate_inclusion(:type, @types)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_length(:item, max: 120)
    |> validate_length(:text, max: 200)
    |> validate_number(:min_spend_cents, greater_than: 0, less_than_or_equal_to: 100_000_000)
    |> validate_number(:max_discount_cents, greater_than: 0, less_than_or_equal_to: 100_000_000)
    |> by_type()
  end

  defp by_type(changeset) do
    case get_field(changeset, :type) do
      "percent" ->
        changeset
        |> validate_required([:percent])
        |> validate_number(:percent, greater_than: 0, less_than_or_equal_to: 100)

      "fixed_amount" ->
        changeset
        |> validate_required([:amount_cents])
        |> validate_number(:amount_cents, greater_than: 0, less_than_or_equal_to: 10_000_000)

      "free_item" ->
        validate_required(changeset, [:item])

      "buy_x_get_y" ->
        changeset
        |> validate_required([:buy_quantity, :get_quantity])
        |> validate_number(:buy_quantity, greater_than: 0, less_than_or_equal_to: 100)
        |> validate_number(:get_quantity, greater_than: 0, less_than_or_equal_to: 100)

      "free_text" ->
        validate_required(changeset, [:text])

      _other ->
        changeset
    end
  end

  defp upcase(value) when is_binary(value), do: String.upcase(value)
  defp upcase(value), do: value
end
