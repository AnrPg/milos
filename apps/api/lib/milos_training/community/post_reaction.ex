defmodule MilosTraining.Community.PostReaction do
  @moduledoc "Kudos on a post (ADR-138)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_post_reactions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :post_id, :binary_id
    field :user_id, :binary_id
    field :kind, :string, default: "kudos"

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
