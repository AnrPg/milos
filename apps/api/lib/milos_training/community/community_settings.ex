defmodule MilosTraining.Community.CommunitySettings do
  @moduledoc """
  A gym's community rules (ADR-143, board 7 Q3): whether members may start
  groups in the gym's club, and whether staff approve them first; whether
  the gym's verified clubs offer Partners (ADR-169, on by default).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @member_groups ~w(none approval free)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :member_groups, :string, default: "approval"
    field :partners_enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, attrs) do
    settings
    |> cast(attrs, [:organization_id, :member_groups, :partners_enabled])
    |> validate_required([:member_groups])
    |> validate_inclusion(:member_groups, @member_groups)
  end

  def member_group_options, do: @member_groups
  def fields, do: [:member_groups, :partners_enabled]
  def defaults, do: %{member_groups: "approval", partners_enabled: true}
end
