defmodule MilosTraining.Identity do
  alias MilosTraining.Identity.Commands.{RegisterUser, UpdateRole}
  alias MilosTraining.Identity.Queries.FindUser
  alias MilosTraining.Identity.UserStore

  defdelegate register(params), to: RegisterUser, as: :call
  defdelegate find_by_nickname(nickname), to: FindUser, as: :by_nickname
  defdelegate find_by_id(id), to: FindUser, as: :by_id
  defdelegate delete(user), to: UserStore, as: :delete_user
  defdelegate update_role(user, role), to: UpdateRole, as: :call
end
