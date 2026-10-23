defmodule Palee.Perks.Rules.Window do
  @moduledoc "A weekly window: ISO weekdays (1 = Monday) and a local time range."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :weekdays, {:array, :integer}, default: [1, 2, 3, 4, 5, 6, 7]
    field :starts_at, :time
    field :ends_at, :time
  end

  def changeset(window, attrs) do
    window
    |> cast(attrs, [:weekdays, :starts_at, :ends_at])
    |> validate_required([:weekdays, :starts_at, :ends_at])
    |> validate_length(:weekdays, min: 1, max: 7)
    |> validate_change(:weekdays, fn :weekdays, days ->
      if Enum.all?(days, &(&1 in 1..7)), do: [], else: [weekdays: "must be 1 (Monday) to 7"]
    end)
    |> validate_range()
  end

  defp validate_range(changeset) do
    from = get_field(changeset, :starts_at)
    until = get_field(changeset, :ends_at)

    if from && until && Time.compare(until, from) != :gt,
      do: add_error(changeset, :ends_at, "must be after the start"),
      else: changeset
  end
end
