defmodule Palee.Perks.Redemption do
  @moduledoc """
  The settings of a perk version's redemption method (ADR-191 §2), a
  validated document with its own `schema_version`. Which fields matter is
  the method strategy's call (`Domain.RedemptionMethod.validate/2`):
  `shared_code` (shared code, partner link), `link_url` (partner link),
  `low_pool_threshold` (code pool), `instructions` for the member (any).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.PromotionCode
  alias Palee.Perks.Domain.RedemptionMethod

  @schema_version 1
  @fields ~w(shared_code link_url low_pool_threshold instructions)a

  @primary_key false
  embedded_schema do
    field :schema_version, :integer, default: @schema_version
    field :shared_code, :string
    field :link_url, :string
    field :low_pool_threshold, :integer
    field :instructions, :string
  end

  @type t :: %__MODULE__{}

  def schema_version, do: @schema_version
  def fields, do: @fields

  @doc "Casts the settings and asks the method's strategy what is missing."
  def changeset(redemption \\ %__MODULE__{}, attrs, method) do
    changeset =
      redemption
      |> cast(attrs, @fields)
      |> put_change(:schema_version, @schema_version)
      |> update_change(:shared_code, &PromotionCode.normalize_code/1)
      |> validate_length(:shared_code, min: 1, max: 64)
      |> validate_length(:link_url, max: 1_000)
      |> validate_length(:instructions, max: 500)

    case RedemptionMethod.validate(method, apply_changes(changeset) |> Map.from_struct()) do
      {:error, :invalid_redemption_method} ->
        add_error(changeset, :redemption_method, "is invalid")

      errors ->
        Enum.reduce(errors, changeset, fn {field, message}, acc -> add_error(acc, field, message) end)
    end
  end
end
