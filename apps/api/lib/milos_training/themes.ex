defmodule MilosTraining.Themes do
  @moduledoc """
  The app's colour themes (shared kernel). A gym picks one for its members
  (gamification settings); a member may pick their own in Ρυθμίσεις, which
  wins on their devices.
  """

  @slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

  def slugs, do: @slugs
  def valid?(slug), do: slug in @slugs
end
