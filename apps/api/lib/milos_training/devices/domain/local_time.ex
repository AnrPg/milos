defmodule MilosTraining.Devices.Domain.LocalTime do
  @moduledoc """
  Devices report an instant and the wearer's UTC offset then, not a zone
  name. The local day comes from the offset; the zone stored with an entry
  is the matching fixed `Etc/GMT±N` zone for whole hours (its sign is
  inverted by convention) and `UTC` otherwise.
  """

  @doc "The fixed zone name for an offset in seconds."
  def zone(0), do: "UTC"

  def zone(offset)
      when is_integer(offset) and rem(offset, 3600) == 0 and abs(offset) <= 14 * 3600 do
    hours = div(offset, 3600)
    if hours > 0, do: "Etc/GMT-#{hours}", else: "Etc/GMT+#{-hours}"
  end

  def zone(_offset), do: "UTC"

  @doc "The wearer's calendar day at `at` with `offset` seconds from UTC."
  def date(%DateTime{} = at, offset) when is_integer(offset),
    do: at |> DateTime.add(offset, :second) |> DateTime.to_date()
end
