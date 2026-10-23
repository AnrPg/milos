defmodule Palee.Perks.PerkCode do
  @moduledoc """
  One single-use code of a perk's pool (ADR-191): the codes a partner hands
  over for a perk redeemed with a unique code per member. A claim takes the
  oldest free one, under the perk's lock.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "perk_codes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :perk_id, :binary_id
    field :code, :string
    field :claim_id, :binary_id
    field :assigned_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @max_codes 5_000
  @max_length 64

  @doc "Most codes one upload may add."
  def max_codes, do: @max_codes

  @doc """
  The canonical, de-duplicated codes of an upload (the discount-code
  normalisation of Finance), or `{:error, :invalid_perk_codes}` when one is
  empty or too long, or the upload is empty or too big.
  """
  def normalize_all(codes) when is_list(codes) and codes != [] and length(codes) <= @max_codes do
    normalized =
      Enum.map(codes, fn
        code when is_binary(code) -> Palee.Finance.PromotionCode.normalize_code(code)
        _other -> nil
      end)

    if Enum.all?(normalized, &(is_binary(&1) and &1 != "" and byte_size(&1) <= @max_length)),
      do: {:ok, Enum.uniq(normalized)},
      else: {:error, :invalid_perk_codes}
  end

  def normalize_all(_codes), do: {:error, :invalid_perk_codes}
end
