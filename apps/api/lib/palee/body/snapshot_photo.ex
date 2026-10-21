defmodule Palee.Body.SnapshotPhoto do
  @moduledoc """
  A photo of a body snapshot (ADR-158): the person's private upload and a
  copy of its renditions' keys, so a coach allowed to see it can be given
  short-lived signed URLs without reading the person's media rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Body.Domain.SnapshotPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "body_snapshot_photos" do
    field :user_id, :binary_id
    field :snapshot_id, :binary_id
    field :media_id, :binary_id
    field :pose, :string
    field :status, :string, default: "processing"
    field :variants, :map, default: %{}
    field :width, :integer
    field :height, :integer
    field :placeholder, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(photo \\ %__MODULE__{}, attrs) do
    photo
    |> cast(attrs, [
      :user_id,
      :snapshot_id,
      :media_id,
      :pose,
      :status,
      :variants,
      :width,
      :height,
      :placeholder
    ])
    |> validate_required([:user_id, :snapshot_id, :media_id, :pose, :status])
    |> validate_inclusion(:pose, SnapshotPolicy.poses())
    |> validate_inclusion(:status, SnapshotPolicy.photo_statuses())
    |> unique_constraint(:media_id)
  end
end
