defmodule MilosTraining.Execution.ProgressOperation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "execution_progress_operations" do
    field :operation_id, :binary_id
    field :execution_id, :binary_id
    field :user_id, :binary_id
    field :base_version, :integer
    field :result_version, :integer
    timestamps(updated_at: false)
  end

  def changeset(operation \\ %__MODULE__{}, attrs) do
    operation
    |> cast(attrs, [:operation_id, :execution_id, :user_id, :base_version, :result_version])
    |> validate_required([:operation_id, :execution_id, :user_id, :base_version, :result_version])
    |> unique_constraint([:execution_id, :user_id, :operation_id],
      name: :execution_progress_operations_idempotency_index
    )
  end
end
