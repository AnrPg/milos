defmodule MilosTraining.Community.ProfilePost do
  @moduledoc """
  A post to the author's followers or to everyone (ADR-142). It belongs to
  its author, not to a gym, so it follows them across gyms.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @audiences ~w(followers public)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_profile_posts" do
    field :user_id, :binary_id
    field :audience, :string
    field :body, :string
    field :attachment_type, :string
    field :attachment_id, :binary_id
    field :attachment, :map
    field :client_operation_id, :string
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def audiences, do: @audiences

  def changeset(post \\ %__MODULE__{}, attrs) do
    post
    |> cast(attrs, [
      :user_id,
      :audience,
      :body,
      :attachment_type,
      :attachment_id,
      :attachment,
      :client_operation_id
    ])
    |> update_change(:body, &trim/1)
    |> validate_required([:user_id, :audience])
    |> validate_inclusion(:audience, @audiences)
    |> validate_inclusion(:attachment_type, MilosTraining.Community.Post.attachment_types())
    |> validate_length(:body, max: 5_000)
    |> validate_length(:client_operation_id, max: 120)
    |> validate_content()
    |> check_constraint(:body, name: :community_profile_posts_content_check)
    |> check_constraint(:attachment_type, name: :community_profile_posts_attachment_check)
    |> unique_constraint(:client_operation_id,
      name: :community_profile_posts_client_operation_index
    )
  end

  defp trim(nil), do: nil

  defp trim(body) do
    case String.trim(body) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_content(changeset) do
    if is_nil(get_field(changeset, :body)) and is_nil(get_field(changeset, :attachment_type)),
      do: add_error(changeset, :body, "can't be blank"),
      else: changeset
  end
end
