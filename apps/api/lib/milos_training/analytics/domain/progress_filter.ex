defmodule MilosTraining.Analytics.Domain.ProgressFilter do
  @moduledoc """
  The Πρόοδος filter (ADR-162, vision §7.2): `range` (`4w 12w 6m 1y all`,
  default `all`, as the per-provider page always counted everything),
  `sources` (provider ids, `freeform`, `device`; none = «Όλοι») and
  `exercise` (a name, normalised substring of the workout's exercises or a
  PR's name). Versioned and stored like the other typed filters (ADR-151).
  """

  alias MilosTraining.Identity.Domain.FilterFields

  @version 1
  @ranges ~w(4w 12w 6m 1y all)

  defstruct version: @version, range: "all", sources: [], exercise: nil

  def ranges, do: @ranges

  def parse(nil), do: parse(%{})

  def parse(params) when is_map(params) do
    params = FilterFields.stringify(params)

    with :ok <- FilterFields.version(params["v"], @version),
         {:ok, range} <- range(params["range"]),
         {:ok, sources} <- FilterFields.sources(:sources, params["sources"]),
         {:ok, exercise} <- FilterFields.text(:exercise, params["exercise"], 2, 80) do
      {:ok, %__MODULE__{range: range, sources: sources, exercise: exercise}}
    end
  end

  def parse(_params), do: {:error, [filter: "must be an object"]}

  def to_params(%__MODULE__{} = filter),
    do: %{
      "v" => filter.version,
      "range" => filter.range,
      "sources" => filter.sources,
      "exercise" => filter.exercise
    }

  def active_count(%__MODULE__{} = filter),
    do:
      Enum.count([filter.range != "all", filter.sources != [], not is_nil(filter.exercise)], & &1)

  @doc "The first day the range covers, given today (nil for `all`)."
  def since(%__MODULE__{range: "all"}, _today), do: nil
  def since(%__MODULE__{range: "4w"}, today), do: Date.add(today, -28)
  def since(%__MODULE__{range: "12w"}, today), do: Date.add(today, -84)
  def since(%__MODULE__{range: "6m"}, today), do: Date.shift(today, month: -6)
  def since(%__MODULE__{range: "1y"}, today), do: Date.shift(today, year: -1)

  defp range(nil), do: {:ok, "all"}
  defp range(""), do: {:ok, "all"}
  defp range(value) when value in @ranges, do: {:ok, value}
  defp range(_value), do: {:error, [range: "has an unknown value"]}
end
