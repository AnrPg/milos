defmodule MilosTraining.Partners.Swipe do
  @moduledoc "One person's like or pass on another in a club (ADR-169)."

  use Ecto.Schema
  import Ecto.Changeset

  @directions ~w(like pass)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "partner_swipes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :swiper_id, :binary_id
    field :target_id, :binary_id
    field :direction, :string

    timestamps(type: :utc_datetime_usec)
  end

  def directions, do: @directions

  def changeset(swipe \\ %__MODULE__{}, attrs) do
    swipe
    |> cast(attrs, [:organization_id, :club_id, :swiper_id, :target_id, :direction])
    |> validate_required([:club_id, :swiper_id, :target_id, :direction])
    |> validate_inclusion(:direction, @directions)
    |> check_constraint(:target_id, name: :partner_swipes_pair_check)
  end
end
