defmodule MilosTraining.Identity.Queries.FindUser do
  alias MilosTraining.Identity.UserStore

  def by_nickname(nickname), do: UserStore.get_by_nickname(nickname)
  def by_id(id), do: UserStore.get_by_id(id)
end
