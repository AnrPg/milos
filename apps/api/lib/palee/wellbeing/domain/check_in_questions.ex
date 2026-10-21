defmodule Palee.Wellbeing.Domain.CheckInQuestions do
  @moduledoc """
  The Πώς νιώθω questionnaire (ADR-140 §2): a catalog of fixed keys, each
  answered on a four-point scale from 1 (worst) to 4 (best) with no neutral
  middle, plus optional free text. Questions live here rather than in the
  database, so adding one needs no migration; the web labels them by key.
  """

  # Order is the order the form shows them in.
  @questions ~w(sleep energy mood stress body)
  @values 1..4
  @note_max 1000

  def keys, do: @questions
  def values, do: Enum.to_list(@values)
  def note_max, do: @note_max
  def known?(key), do: key in @questions
  def order(key), do: Enum.find_index(@questions, &(&1 == key))

  def catalog do
    Enum.map(@questions, fn key ->
      %{key: key, min: @values.first, max: @values.last}
    end)
  end
end
