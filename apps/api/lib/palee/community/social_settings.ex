defmodule Palee.Community.SocialSettings do
  @moduledoc """
  A member's social choices that follow them across gyms (ADR-142): whether
  followers see which classes they book (the «Φίλοι» chip), and whether they
  show in clubs' «Μέλη» lists (ADR-143, board 7 Q1), and whether their
  public posts show in Γύρω μου at their neighbourhood (ADR-154).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :binary_id, autogenerate: false}

  schema "community_social_settings" do
    field :share_bookings, :boolean, default: false
    field :share_bookings_offered_at, :utc_datetime_usec
    field :hide_from_members, :boolean, default: false
    field :visible_around, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, attrs) do
    settings
    |> cast(attrs, [
      :user_id,
      :share_bookings,
      :share_bookings_offered_at,
      :hide_from_members,
      :visible_around
    ])
    |> validate_required([:user_id, :share_bookings])
  end
end
