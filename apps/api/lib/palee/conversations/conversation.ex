defmodule Palee.Conversations.Conversation do
  @moduledoc """
  One person-to-person conversation (ADR-193 §3): the pair, ordered
  `user_a_id < user_b_id`, each side's folder and read mark, who started it
  and the latest message. Account-scoped: only the two people read it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Conversations.Domain.ConversationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "person_conversations" do
    field :user_a_id, :binary_id
    field :user_b_id, :binary_id
    field :started_by_id, :binary_id
    field :a_folder, :string
    field :b_folder, :string
    field :a_read_at, :utc_datetime_usec
    field :b_read_at, :utc_datetime_usec
    field :last_message_at, :utc_datetime_usec
    field :last_author_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @create ~w(user_a_id user_b_id started_by_id a_folder b_folder)a
  @change ~w(a_folder b_folder a_read_at b_read_at last_message_at last_author_id)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create)
    |> validate_required(@create)
    |> validate_inclusion(:a_folder, ConversationPolicy.folders())
    |> validate_inclusion(:b_folder, ConversationPolicy.folders())
    |> unique_constraint([:user_a_id, :user_b_id])
    |> check_constraint(:user_a_id, name: :person_conversations_pair_check)
  end

  def change_changeset(conversation, changes) do
    conversation
    |> cast(changes, @change)
    |> validate_inclusion(:a_folder, ConversationPolicy.folders())
    |> validate_inclusion(:b_folder, ConversationPolicy.folders())
  end
end
