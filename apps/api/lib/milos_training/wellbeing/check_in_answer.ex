defmodule MilosTraining.Wellbeing.CheckInAnswer do
  @moduledoc "One answer of a Πώς νιώθω submission: a catalog question, 1–4, optional text."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Wellbeing.Domain.CheckInQuestions

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wellbeing_check_in_answers" do
    field(:check_in_id, :binary_id)
    field(:user_id, :binary_id)
    field(:question_key, :string)
    field(:value, :integer)
    field(:note, :string)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(%__MODULE__{} = answer, attrs) do
    answer
    |> cast(attrs, [:user_id, :question_key, :value, :note])
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:user_id, :question_key, :value])
    |> validate_inclusion(:question_key, CheckInQuestions.keys())
    |> validate_inclusion(:value, CheckInQuestions.values())
    |> validate_length(:note, max: CheckInQuestions.note_max())
    |> check_constraint(:value, name: :wellbeing_check_in_answers_value_check)
    |> unique_constraint(:question_key,
      name: :wellbeing_check_in_answers_check_in_id_question_key_index
    )
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
