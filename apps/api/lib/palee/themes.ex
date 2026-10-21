defmodule Palee.Themes do
  @moduledoc """
  The app's colour themes (shared kernel). Palee wears one brand palette for
  gyms and members alike, in a light ("frost", the default) and a dark
  ("graphite") variant. A member may pick the dark one in Ρυθμίσεις; gyms do
  not choose a theme.
  """

  @slugs ~w(frost graphite)
  @default "frost"

  def slugs, do: @slugs
  def default, do: @default
  def valid?(slug), do: slug in @slugs
end
