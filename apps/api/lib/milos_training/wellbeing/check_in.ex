defmodule MilosTraining.Wellbeing.CheckIn do
  @moduledoc """
  Πώς νιώθω (ADR-139, feature map): a ten-second readiness check of sleep,
  energy, mood and stress. Any subset may be given, at least one. Private by
  default; written in a gym (provenance) or personally; soft-deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @scales ~w(sleep_quality energy mood stress)a
  @values [:sleep_hours | @scales]

  schema "wellbeing_check_ins" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:sleep_hours, :decimal)
    field(:sleep_quality, :integer)
    field(:energy, :integer)
    field(:mood, :integer)
    field(:stress, :integer)
    field(:note, :string)
    field(:recorded_at, :utc_datetime_usec)
    field(:recorded_tz, :string, default: "UTC")
    field(:journal_visibility, :string, default: "private")
    field(:deleted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def values, do: @values

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :note,
      :recorded_at,
      :recorded_tz,
      :journal_visibility | @values
    ])
    |> validate_required([:user_id, :recorded_at, :journal_visibility])
    |> validate_values()
    |> foreign_key_constraint(:organization_id)
  end

  def visibility_changeset(%__MODULE__{} = check_in, rung) do
    check_in
    |> change(journal_visibility: rung)
    |> validate_inclusion(:journal_visibility, MilosTraining.Journal.visibility_rungs())
    |> check_constraint(:journal_visibility,
      name: :wellbeing_check_ins_journal_visibility_check
    )
  end

  def delete_changeset(%__MODULE__{} = check_in, %DateTime{} = now),
    do: change(check_in, deleted_at: now)

  defp validate_values(changeset) do
    changeset =
      Enum.reduce(@scales, changeset, fn scale, acc ->
        validate_number(acc, scale, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
      end)

    changeset
    |> validate_number(:sleep_hours, greater_than_or_equal_to: 0, less_than_or_equal_to: 24)
    |> update_change(:note, &blank_to_nil/1)
    |> validate_length(:note, max: 1000)
    |> validate_any_value()
    |> validate_change(:recorded_tz, fn :recorded_tz, zone ->
      case DateTime.now(zone) do
        {:ok, _now} -> []
        {:error, _reason} -> [recorded_tz: "is not a known time zone"]
      end
    end)
  end

  defp validate_any_value(changeset) do
    if Enum.any?(@values, &(not is_nil(get_field(changeset, &1)))),
      do: changeset,
      else: add_error(changeset, :mood, "give at least one of sleep, energy, mood or stress")
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
