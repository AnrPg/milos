defmodule MilosTraining.Community.SocialSettings do
  @moduledoc """
  A member's social choices that follow them across gyms (ADR-142). For now
  one: whether followers see which classes they book (the «Φίλοι» chip).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :binary_id, autogenerate: false}

  schema "community_social_settings" do
    field :share_bookings, :boolean, default: false
    field :share_bookings_offered_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, attrs) do
    settings
    |> cast(attrs, [:user_id, :share_bookings, :share_bookings_offered_at])
    |> validate_required([:user_id, :share_bookings])
  end
end
