defmodule Palee.Content.Video do
  @moduledoc "An on-demand video item linked from an external host (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Content.Domain.VideoPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "content_videos" do
    field :organization_id, :binary_id
    field :title, :string
    field :description, :string
    field :video_url, :string
    field :duration_minutes, :integer
    field :tags, {:array, :string}, default: []
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:title, :description, :video_url, :duration_minutes, :tags]

  def create_changeset(video \\ %__MODULE__{}, params) do
    video
    |> cast(params, [:organization_id, :created_by_id | @fields])
    |> validate_required([:organization_id])
    |> validate_fields()
  end

  def update_changeset(video, params) do
    video
    |> cast(params, @fields)
    |> validate_fields()
  end

  def publication_changeset(video, published_at), do: change(video, published_at: published_at)
  def archive_changeset(video, archived_at), do: change(video, archived_at: archived_at)

  defp validate_fields(changeset) do
    changeset
    |> update_change(:title, &String.trim/1)
    |> update_change(:tags, &VideoPolicy.normalize_tags/1)
    |> validate_required([:title, :video_url])
    |> validate_length(:title, min: 2, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_change(:video_url, fn :video_url, url ->
      if VideoPolicy.valid_url?(url), do: [], else: [video_url: "must be an https link"]
    end)
  end
end
