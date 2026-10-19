defmodule MilosTraining.Organizations.TagSuggestion do
  @moduledoc """
  A tag an owner could not find in the canonical lists (board 3b Q5,
  «Δεν το βρίσκεις; Πρότεινέ το»). It never shows on the page; the platform
  reviews it and adds the tag to the list for every gym, or declines it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.BoxProfilePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "profile_tag_suggestions" do
    field :organization_id, :binary_id
    field :suggested_by_id, :binary_id
    field :list, :string
    field :name, :string
    field :status, :string, default: "pending"
    field :resolved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(suggestion, params) do
    suggestion
    |> cast(params, [:organization_id, :suggested_by_id, :list, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:organization_id, :list, :name])
    |> validate_inclusion(:list, BoxProfilePolicy.suggestion_lists())
    |> validate_length(:name, min: 2, max: 60)
  end
end
