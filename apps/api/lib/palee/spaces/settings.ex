defmodule Palee.Spaces.Settings do
  @moduledoc """
  The gym's choices about its spaces (ADR-290): whether the people who see a
  class may open the floor plan with the class's room coloured on it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  # One row per gym (unique organization_id).
  schema "space_settings" do
    field :organization_id, :binary_id
    field :floor_plans_in_classes, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:floor_plans_in_classes])
    |> validate_required([:floor_plans_in_classes])
  end
end
