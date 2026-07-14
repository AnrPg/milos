defmodule MilosTraining.Feedback.ReviewQuestionnaire do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "review_questionnaires" do
    field :target_type, :string
    field :version, :integer, default: 1
    field :questions, {:array, :map}, default: []
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(questionnaire \\ %__MODULE__{}, params) do
    questionnaire
    |> cast(params, [:target_type, :version, :questions, :active])
    |> validate_required([:target_type, :version, :questions, :active])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:target_type, :version])
  end
end
