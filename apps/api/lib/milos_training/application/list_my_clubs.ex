defmodule MilosTraining.Application.ListMyClubs do
  @moduledoc """
  `GET /api/me/clubs` (ADR-138): the clubs of every gym the member actively
  belongs to, read in their personal session (see `ClubScope`).
  """

  alias MilosTraining.Application.ClubScope

  def call(context), do: ClubScope.call(context)
end
