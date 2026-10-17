defmodule MilosTraining.Media.AccountObject do
  @moduledoc "An image a person owns: body photos (ADR-148). Deleted with the account."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Media.Domain.MediaPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "media_account_objects" do
    field :user_id, :binary_id
    field :purpose, :string
    field :object_key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer
    field :status, :string, default: "pending"
    field :attached_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:id, :user_id, :purpose, :object_key, :content_type])
    |> validate_required([:id, :user_id, :purpose, :object_key, :content_type])
    |> validate_inclusion(:purpose, MediaPolicy.account_purposes())
    |> unique_constraint(:object_key)
  end
end
