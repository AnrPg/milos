defmodule Palee.Anatomy.Domain.FitnessQualities do
  @moduledoc """
  The ten general physical skills used by WOD goals and the qualities radar
  (ADR-163, brief §7.6). Ids are stable; labels are translated on the client
  (`anatomy.quality.<id>`).
  """

  @qualities [
    "cardiorespiratory-endurance",
    "stamina",
    "strength",
    "flexibility",
    "power",
    "speed",
    "coordination",
    "agility",
    "balance",
    "accuracy"
  ]

  def all, do: @qualities

  def known?(id), do: id in @qualities

  @doc "Keeps known qualities, in canonical order, without duplicates."
  def normalize(ids) when is_list(ids) do
    wanted = MapSet.new(ids)
    Enum.filter(@qualities, &MapSet.member?(wanted, &1))
  end

  def normalize(_ids), do: []
end
