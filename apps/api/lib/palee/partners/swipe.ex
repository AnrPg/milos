defmodule Palee.Partners.Swipe do
  @moduledoc "One person's like or pass on another in the public deck (ADR-169, ADR-280)."

  use Ecto.Schema
  import Ecto.Changeset

  @directions ~w(like pass)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_swipes" do
    field :swiper_id, :binary_id
    field :target_id, :binary_id
    field :direction, :string

    timestamps(type: :utc_datetime_usec)
  end

  def directions, do: @directions

  def changeset(swipe \\ %__MODULE__{}, attrs) do
    swipe
    |> cast(attrs, [:swiper_id, :target_id, :direction])
    |> validate_required([:swiper_id, :target_id, :direction])
    |> validate_inclusion(:direction, @directions)
    |> check_constraint(:target_id, name: :partner_swipes_pair_check)
  end
end
