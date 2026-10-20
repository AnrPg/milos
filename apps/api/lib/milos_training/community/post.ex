defmodule MilosTraining.Community.Post do
  @moduledoc "A post in a club channel (ADR-138)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Community.Domain.PostMediaPolicy

  @audiences ~w(club_channel followers public)
  # Journal entries a member shares, and the card of a club event (ADR-153).
  @shareable_attachment_types ~w(training_log_entry workout_execution pr)
  @attachment_types @shareable_attachment_types ++ ["event"]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_posts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :channel_id, :binary_id
    field :author_id, :binary_id
    field :audience, :string, default: "club_channel"
    field :body, :string
    field :attachment_type, :string
    field :attachment_id, :binary_id
    field :attachment, :map
    field :client_operation_id, :string
    # ADR-157: the post's photos or video, in order, and whether it shows yet.
    field :media, {:array, :map}, default: []
    field :media_status, :string, default: "ready"
    field :pinned_at, :utc_datetime_usec
    field :hidden_at, :utc_datetime_usec
    field :hidden_by_id, :binary_id
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post \\ %__MODULE__{}, attrs) do
    post
    |> cast(attrs, [
      :organization_id,
      :club_id,
      :channel_id,
      :author_id,
      :audience,
      :body,
      :attachment_type,
      :attachment_id,
      :attachment,
      :media,
      :media_status,
      :client_operation_id,
      :pinned_at
    ])
    |> update_change(:body, &trim/1)
    |> validate_required([:club_id, :channel_id, :author_id, :audience])
    |> validate_inclusion(:audience, @audiences)
    |> validate_inclusion(:attachment_type, @attachment_types)
    |> validate_length(:body, max: 5_000)
    |> validate_length(:client_operation_id, max: 120)
    |> validate_length(:media, max: PostMediaPolicy.max_images())
    |> validate_inclusion(:media_status, PostMediaPolicy.statuses())
    |> validate_content()
    |> check_constraint(:body, name: :community_posts_content_check)
    |> check_constraint(:attachment_type, name: :community_posts_attachment_check)
    |> unique_constraint(:client_operation_id, name: :community_posts_client_operation_index)
  end

  def moderation_changeset(post, attrs),
    do: cast(post, attrs, [:hidden_at, :hidden_by_id, :deleted_at, :pinned_at])

  def attachment_types, do: @attachment_types
  def shareable_attachment_types, do: @shareable_attachment_types

  @doc "ADR-157: the post's media snapshot and status."
  def media_changeset(post, attrs) do
    post
    |> cast(attrs, [:media, :media_status])
    |> validate_required([:media_status])
    |> validate_length(:media, max: PostMediaPolicy.max_images())
    |> validate_inclusion(:media_status, PostMediaPolicy.statuses())
  end

  defp trim(nil), do: nil

  defp trim(body) do
    case String.trim(body) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_content(changeset) do
    if is_nil(get_field(changeset, :body)) and is_nil(get_field(changeset, :attachment_type)) and
         get_field(changeset, :media) in [nil, []],
       do: add_error(changeset, :body, "can't be blank"),
       else: changeset
  end
end
