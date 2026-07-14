defmodule MilosTraining.Feedback.ReviewAnswer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "review_answers" do
    field :review_id, :binary_id
    field :question_key, :string
    field :question_text, :string
    field :answer_text, :string
    field :rating_value, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review_answer \\ %__MODULE__{}, params) do
    review_answer
    |> cast(params, [:review_id, :question_key, :question_text, :answer_text, :rating_value])
    |> validate_required([:review_id, :question_key, :question_text])
    |> validate_number(:rating_value, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> foreign_key_constraint(:review_id)
  end
end
