defmodule Palee.Buddies.Message do
  @moduledoc "One message of a buddy link's own conversation (ADR-160 §2)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Buddies.Domain.MessagePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "buddy_messages" do
    field :link_id, :binary_id
    field :user_id, :binary_id
    field :buddy_user_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(link_id user_id buddy_user_id author_id body)a

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_length(:body, min: 1, max: MessagePolicy.body_max())
  end
end
