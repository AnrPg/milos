defmodule MilosTraining.Application.ListAthletes do
  alias MilosTraining.Identity

  def call(query), do: Identity.search_athletes(query)
end
