defmodule Palee.Themes do
  @moduledoc """
  The app's colour themes (shared kernel). A gym picks one for its members
  (gamification settings); a member may pick their own in Ρυθμίσεις, which
  wins on their devices.
  """

  # "frost" (light) and "graphite" (dark) are the Palee brand palette;
  # frost is the default for new gyms and for anyone without a choice.
  @slugs ~w(frost graphite ember sage steel aurora royal volt noir daybreak paper lagoon sunset)
  @default "frost"

  def slugs, do: @slugs
  def default, do: @default
  def valid?(slug), do: slug in @slugs
end
