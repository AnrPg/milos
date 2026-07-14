defmodule MilosTraining.Identity.Queries.FindUser do
  alias MilosTraining.Identity.UserStore

  def by_nickname(nickname), do: UserStore.get_by_nickname(nickname)
  def by_id(id), do: UserStore.get_by_id(id)
  def list_by_ids(ids), do: UserStore.list_by_ids(ids)
  def list_by_role(role), do: UserStore.list_by_role(role)
  def list_all, do: UserStore.list_all_users()

  def search_athletes(query) do
    UserStore.search_athletes(query)
    |> Enum.map(fn athlete ->
      %{id: athlete.id, nickname: athlete.nickname, role: to_string(athlete.role)}
    end)
  end
end
