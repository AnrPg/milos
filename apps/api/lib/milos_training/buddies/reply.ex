defmodule MilosTraining.Buddies.Reply do
  @moduledoc "A buddy's answer to a support request (ADR-160)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Buddies.Domain.SupportPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "support_replies" do
    field :request_id, :binary_id
    field :user_id, :binary_id
    field :buddy_user_id, :binary_id
    field :kind, :string
    field :text, :string
    field :thread_id, :binary_id
    field :conversation_organization_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(request_id user_id buddy_user_id kind text thread_id conversation_organization_id)a

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([:request_id, :user_id, :buddy_user_id, :kind])
    |> validate_inclusion(:kind, SupportPolicy.reply_kinds())
    |> validate_length(:text, min: 1, max: SupportPolicy.reply_text_max())
  end
end
