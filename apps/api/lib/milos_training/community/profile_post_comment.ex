defmodule MilosTraining.Community.ProfilePostComment do
  @moduledoc "A comment on a profile post (ADR-142); `user_id` is its author."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_profile_post_comments" do
    field :post_id, :binary_id
    field :user_id, :binary_id
    field :body, :string
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment \\ %__MODULE__{}, attrs) do
    comment
    |> cast(attrs, [:post_id, :user_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:post_id, :user_id, :body])
    |> validate_length(:body, min: 1, max: 2_000)
  end
end
