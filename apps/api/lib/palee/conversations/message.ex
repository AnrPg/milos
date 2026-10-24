defmodule Palee.Conversations.Message do
  @moduledoc "One immutable message of a person conversation (ADR-193 §3)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Conversations.Domain.ConversationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "person_messages" do
    field :conversation_id, :binary_id
    field :user_a_id, :binary_id
    field :user_b_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    field :client_operation_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required ~w(conversation_id user_a_id user_b_id author_id body)a

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:client_operation_id | @required])
    |> validate_required(@required)
    |> validate_length(:body, min: 1, max: ConversationPolicy.body_max())
    |> unique_constraint([:author_id, :client_operation_id],
      name: :person_messages_client_operation_index
    )
  end
end
