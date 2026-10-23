defmodule Palee.Interests.Domain.InterestsPolicy do
  @moduledoc """
  Rules of a person's interests (ADR-183). Disciplines are keys of the shared
  box vocabulary (ADR-142), so what a person does and what a box offers meet
  in Γύρω μου; the caller passes that vocabulary in. Levels are the Partners
  levels (ADR-169). Both are keys; clients translate them.
  """

  @levels ~w(beginner intermediate advanced)
  @max_disciplines 12

  def levels, do: @levels
  def max_disciplines, do: @max_disciplines

  def empty, do: %{disciplines: [], level: nil}

  @doc """
  Parses `%{"disciplines" => [...], "level" => ...}` against the known
  `disciplines`. Both keys are required: the request replaces the whole set.
  Duplicates collapse, order is the person's; `level` may be nil.
  """
  def normalize(params, disciplines) when is_map(params) do
    with {:ok, picked} <- parse_disciplines(Map.get(params, "disciplines"), disciplines),
         {:ok, level} <- parse_level(Map.fetch(params, "level")) do
      {:ok, %{disciplines: picked, level: level}}
    end
  end

  def normalize(_params, _disciplines), do: {:error, [disciplines: "must be a list"]}

  defp parse_disciplines(picked, known) when is_list(picked) do
    picked = Enum.uniq(picked)

    cond do
      not Enum.all?(picked, &is_binary/1) -> {:error, [disciplines: "must be keys"]}
      Enum.any?(picked, &(&1 not in known)) -> {:error, [disciplines: "has an unknown key"]}
      length(picked) > @max_disciplines -> {:error, [disciplines: "at most #{@max_disciplines}"]}
      true -> {:ok, picked}
    end
  end

  defp parse_disciplines(_picked, _known), do: {:error, [disciplines: "must be a list"]}

  defp parse_level({:ok, nil}), do: {:ok, nil}
  defp parse_level({:ok, level}) when level in @levels, do: {:ok, level}
  defp parse_level({:ok, _level}), do: {:error, [level: "is not a level"]}
  defp parse_level(:error), do: {:error, [level: "is required (null for none)"]}
end
