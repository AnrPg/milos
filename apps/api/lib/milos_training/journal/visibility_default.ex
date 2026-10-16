defmodule MilosTraining.Journal.VisibilityDefault do
  @moduledoc "A member's default rung for new entries of one kind (ADR-139)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Journal.Domain.Visibility

  @primary_key false
  @foreign_key_type :binary_id

  schema "journal_visibility_defaults" do
    field(:user_id, :binary_id, primary_key: true)
    field(:kind, :string, primary_key: true)
    field(:visibility, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :kind, :visibility])
    |> validate_required([:user_id, :kind, :visibility])
    |> validate_inclusion(:kind, Visibility.default_kinds())
    |> validate_inclusion(:visibility, Visibility.default_rungs())
  end
end
