defmodule MilosTraining.Gamification.UserGamificationPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_gamification_preferences" do
    field :user_id, :binary_id
    field :off_days, {:array, :integer}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(prefs \\ %__MODULE__{}, params) do
    prefs
    |> cast(params, [:user_id, :off_days])
    |> validate_required([:user_id])
    |> validate_off_days()
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_off_days(changeset) do
    case get_change(changeset, :off_days) do
      nil ->
        changeset

      days ->
        changeset
        |> validate_length_of_off_days(days)
        |> validate_off_day_values(days)
    end
  end

  defp validate_length_of_off_days(changeset, days) when length(days) > 5 do
    add_error(changeset, :off_days, "cannot have more than 5 off days per week")
  end

  defp validate_length_of_off_days(changeset, _days), do: changeset

  defp validate_off_day_values(changeset, days) do
    if Enum.all?(days, &(&1 in 0..6)) do
      changeset
    else
      add_error(changeset, :off_days, "values must be between 0 (Sunday) and 6 (Saturday)")
    end
  end
end
