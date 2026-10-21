defmodule Palee.Wellbeing.CheckIn do
  @moduledoc """
  One Πώς νιώθω submission (ADR-140 §2): an immutable, timestamped set of
  answers. A member may submit any number of times a day; the latest is the
  current state and a correction is a new submission. Private by default;
  written in a gym (provenance) or personally; soft-deleted by its owner.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Wellbeing.CheckInAnswer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wellbeing_check_ins" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:recorded_at, :utc_datetime_usec)
    field(:recorded_tz, :string, default: "UTC")
    field(:journal_visibility, :string, default: "private")
    field(:deleted_at, :utc_datetime_usec)

    has_many(:answers, CheckInAnswer, foreign_key: :check_in_id)

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :organization_id, :recorded_at, :recorded_tz, :journal_visibility])
    |> validate_required([:user_id, :recorded_at, :journal_visibility])
    |> validate_inclusion(:journal_visibility, Palee.Journal.visibility_rungs())
    |> validate_change(:recorded_tz, fn :recorded_tz, zone ->
      case DateTime.now(zone) do
        {:ok, _now} -> []
        {:error, _reason} -> [recorded_tz: "is not a known time zone"]
      end
    end)
    |> cast_assoc(:answers,
      with: &CheckInAnswer.changeset/2,
      required: true,
      required_message: "answer at least one question"
    )
    |> validate_distinct_questions()
    |> foreign_key_constraint(:organization_id)
    |> check_constraint(:journal_visibility,
      name: :wellbeing_check_ins_journal_visibility_check
    )
  end

  def visibility_changeset(%__MODULE__{} = check_in, rung) do
    check_in
    |> change(journal_visibility: rung)
    |> validate_inclusion(:journal_visibility, Palee.Journal.visibility_rungs())
    |> check_constraint(:journal_visibility,
      name: :wellbeing_check_ins_journal_visibility_check
    )
  end

  def delete_changeset(%__MODULE__{} = check_in, %DateTime{} = now),
    do: change(check_in, deleted_at: now)

  defp validate_distinct_questions(changeset) do
    keys =
      changeset
      |> get_change(:answers, [])
      |> Enum.map(&get_field(&1, :question_key))

    if length(keys) == length(Enum.uniq(keys)),
      do: changeset,
      else: add_error(changeset, :answers, "answer each question at most once")
  end
end
