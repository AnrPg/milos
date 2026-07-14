defmodule MilosTraining.Application.SearchUsers do
  alias MilosTraining.Identity

  def call(query) do
    Identity.search_users(query)
  end
end
