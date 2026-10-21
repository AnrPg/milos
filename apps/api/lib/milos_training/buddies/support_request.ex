defmodule MilosTraining.Buddies.SupportRequest do
  @moduledoc """
  One «Χρειάζομαι στήριξη» (ADR-160). `source_ref` is an opaque id of the
  craving it came from; no craving detail is kept here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Buddies.Domain.SupportPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "support_requests" do
    field :user_id, :binary_id
    field :message, :string
    field :source, :string, default: "quick"
    field :source_ref, :binary_id
    field :undone_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :nudge_sent_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :message, :source, :source_ref, :inserted_at])
    |> validate_required([:user_id, :source])
    |> validate_inclusion(:source, SupportPolicy.sources())
    |> validate_length(:message, min: 1, max: SupportPolicy.message_max())
  end
end
