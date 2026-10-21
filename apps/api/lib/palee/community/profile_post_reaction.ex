defmodule Palee.Community.ProfilePostReaction do
  @moduledoc "Kudos on a profile post (ADR-142)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_profile_post_reactions" do
    field :post_id, :binary_id
    field :user_id, :binary_id
    field :kind, :string, default: "kudos"

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
