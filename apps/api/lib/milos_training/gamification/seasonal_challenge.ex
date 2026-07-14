defmodule MilosTraining.Gamification.SeasonalChallenge do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Gamification.Domain.ChallengeCriteria

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @criteria_types [:workout_count, :workout_type_count, :pr_count, :custom]

  schema "seasonal_challenges" do
    field :title, :string
    field :description, :string
    field :criteria_type, Ecto.Enum, values: @criteria_types
    field :criteria_value, :map, default: %{}
    field :badge_key, :string
    field :badge_label, :string
    field :starts_at, :date
    field :ends_at, :date
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(challenge \\ %__MODULE__{}, params) do
    challenge
    |> cast(params, [
      :title,
      :description,
      :criteria_type,
      :criteria_value,
      :badge_key,
      :badge_label,
      :starts_at,
      :ends_at,
      :created_by_id
    ])
    |> validate_required([
      :title,
      :criteria_type,
      :criteria_value,
      :badge_key,
      :badge_label,
      :starts_at,
      :ends_at
    ])
    |> validate_created_by_id()
    |> validate_length(:title, min: 3, max: 120)
    |> validate_length(:badge_key, min: 3, max: 120)
    |> validate_length(:badge_label, min: 1, max: 120)
    |> validate_criteria_definition()
    |> validate_change(:ends_at, fn :ends_at, ends_at ->
      starts_at = get_field(challenge_changeset(challenge, params), :starts_at)

      if starts_at && Date.compare(ends_at, starts_at) == :lt do
        [ends_at: "must be on or after the start date"]
      else
        []
      end
    end)
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_created_by_id(changeset) do
    if get_field(changeset, :created_by_id) do
      changeset
    else
      add_error(changeset, :created_by_id, "can't be blank")
    end
  end

  defp validate_criteria_definition(changeset) do
    criteria_type = get_field(changeset, :criteria_type)
    criteria_value = get_field(changeset, :criteria_value)

    case ChallengeCriteria.normalize(criteria_type, criteria_value) do
      {:ok, %{criteria_value: normalized_value}} ->
        put_change(changeset, :criteria_value, normalized_value)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {field, message}, acc ->
          add_error(acc, field, message)
        end)
    end
  end

  defp challenge_changeset(challenge, params) do
    change(challenge, %{
      starts_at: params[:starts_at] || params["starts_at"] || challenge.starts_at
    })
  end
end
