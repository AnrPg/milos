defmodule MilosTraining.Messaging.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  # `box`: the gym's thread with one member (context_id is the member);
  # any permitted staff member can continue it (ADR-140 §6).
  @context_types [:direct, :assignment, :class_slot, :box]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_threads" do
    field :organization_id, :binary_id
    field :context_type, Ecto.Enum, values: @context_types
    field :context_id, :binary_id
    field :direct_key, :string
    field :created_by_id, :binary_id

    has_many :participants, MilosTraining.Messaging.Participant, foreign_key: :thread_id
    has_many :messages, MilosTraining.Messaging.Message, foreign_key: :thread_id

    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:organization_id, :context_type, :context_id, :direct_key, :created_by_id])
    |> validate_required([:context_type, :created_by_id])
    |> validate_context_id()
    |> unique_constraint(:direct_key, name: :messaging_threads_organization_direct_key_index)
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_context_id(changeset) do
    case get_field(changeset, :context_type) do
      :direct -> changeset
      nil -> changeset
      _other -> validate_required(changeset, [:context_id])
    end
  end
end
