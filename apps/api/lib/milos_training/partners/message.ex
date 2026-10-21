defmodule MilosTraining.Partners.Message do
  @moduledoc """
  A message in a match's conversation (ADR-169 §7): words, or a «Κλείστε
  μαζί» plan carrying a class and a snapshot of it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(text plan)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "partner_messages" do
    field :organization_id, :binary_id, read_after_writes: true
    field :match_id, :binary_id
    field :author_id, :binary_id
    field :kind, :string, default: "text"
    field :body, :string
    field :scheduled_class_id, :binary_id
    field :plan, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def kinds, do: @kinds

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :match_id,
      :author_id,
      :kind,
      :body,
      :scheduled_class_id,
      :plan
    ])
    |> validate_required([:match_id, :author_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:body, min: 1, max: 2000)
    |> check_constraint(:kind, name: :partner_messages_kind_check)
  end
end
