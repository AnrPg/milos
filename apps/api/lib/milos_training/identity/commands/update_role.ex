defmodule MilosTraining.Identity.Commands.UpdateRole do
  alias MilosTraining.Identity.{Account, UserStore}

  def call(%Account{} = user, role), do: UserStore.update_user_role(user, role)
  def call(user_id, role) when is_binary(user_id), do: UserStore.update_user_role(user_id, role)
end
