defmodule MilosTraining.Community.PostComment do
  @moduledoc "A comment on a post (ADR-138)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_post_comments" do
    field :organization_id, :binary_id, read_after_writes: true
    field :post_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    field :deleted_at, :utc_datetime_usec
    field :hidden_at, :utc_datetime_usec
    field :hidden_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment \\ %__MODULE__{}, attrs) do
    comment
    |> cast(attrs, [:organization_id, :post_id, :author_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:post_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 2_000)
  end
end
